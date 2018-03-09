#=
Basic types for characters and strings

Copyright 2017 Gandalf Software, Inc., Scott P. Jones
Licensed under MIT License, see LICENSE.md

Encodings inspired from collaborations on the following packages:
https://github.com/quinnj/Strings.jl with @quinnj (Jacob Quinn)
https://github.com/nalimilan/StringEncodings.jl with @nalimilan (Milan Bouchet-Valat)
=#
export Str, UniStr, CodePoint, CharSet, Encoding, @cs_str, @enc_str, @cse, charset, encoding
export BIG_ENDIAN, LITTLE_ENDIAN

const BIG_ENDIAN    = (ENDIAN_BOM == 0x01020304)
const LITTLE_ENDIAN = !BIG_ENDIAN

const STR_DATA_VECTOR = false
const STR_KEEP_NUL    = true  # keep nul byte placed by String

struct CharSet{CS}   end
struct Encoding{Enc} end
struct CSE{CS, ENC}  end

CharSet(s)  = CharSet{Symbol(s)}()
Encoding(s) = Encoding{Symbol(s)}()
CSE(cs, e)  = CSE{CharSet(cs), Encoding(e)}()

macro cs_str(s)
    :(CharSet{$(quotesym(s))}())
end
macro enc_str(s)
    :(Encoding{$(quotesym(s))}())
end
macro cse(cs, e)
    :(CSE{CharSet{$(quotesym(cs)), $(quotesym(e))}()})
end

const charsets = (
     :ASCII,   # (7-bit subset of Unicode)
     :Latin,   # ISO-8859-1 (8-bit subset of Unicode)
     :UCS2,    # BMP (16-bit subset of Unicode)
     :UTF32,   # corresponding to codepoints (0-0xd7ff, 0xe000-0x10fff)
     :Text1,   # Unknown character set, 1 byte
     :Text2,   # Unknown character set, 2 byte
     :Text4)   # Unknown character set, 4 byte

for nam in charsets
    @eval const $(symstr(nam, "CharSet")) = CharSet{$(quotesym(nam))}
end

const BinaryCharSet  = CharSet{:Binary}  # really, no character set at all, not text
const UniPlusCharSet = CharSet{:UniPlus} # valid Unicode, plus unknown characters (for String)

# These are to indicate string types that must have at least one character of the type,
# for the internal types to make up the UniStr union type

const LatinSubSet  = CharSet{:LatinSubSet} # Has at least 1 character > 0x7f, all <= 0xff
const UCS2SubSet   = CharSet{:UCS2SubSet}  # Has at least 1 character > 0xff, all <= 0xffff
const UTF32SubSet  = CharSet{:UTF32SubSet} # Has at least 1 non-BMP character in string

const Native1Byte  = Encoding(:Byte)
const NativeUTF8   = Encoding(:UTF8)
@eval show(io::IO, ::Type{NativeUTF8})  = print(io, "UTF-8")
@eval show(io::IO, ::Type{Native1Byte}) = print(io, "8-bit")

for (n, l, b, s) in (("2Byte", :LE2, :BE2, "16-bit"),
                     ("4Byte", :LE4, :BE4, "32-bit"),
                     ("UTF16", :UTF16LE, :UTF16BE, "UTF-16"))
    nat, swp = BIG_ENDIAN ? (b, l) : (l, b)
    natnam = symstr("Native",  n)
    swpnam = symstr("Swapped", n)
    @eval const $natnam = Encoding($(quotesym("N", n)))
    @eval const $swpnam = Encoding($(quotesym("S", n)))
    @eval const $nat = $natnam
    @eval const $swp = $swpnam
    @eval show(io::IO, ::Type{$natnam}) = print(io, $s)
    @eval show(io::IO, ::Type{$swpnam}) = print(io, $(string(s, " ", BIG_ENDIAN ? "LE" : "BE")))
end

const _CSE{U} = Union{CharSet{U}, Encoding{U}} where {U}

print(io::IO, ::S) where {S<:_CSE{U}} where {U} =
    print(io, U)
print(io::IO, ::CSE{CS,E}) where {S,U,CS<:CharSet{S},E<:Encoding{U}} =
    print(io, "CSE{", string(S), ",", string(U), "}()")

show(io::IO, ::Type{CharSet{S}}) where {S}   = print(io, "CharSet{", string(S), "}")
show(io::IO, ::Type{Encoding{S}}) where {S}  = print(io, "Encoding{", string(S), "}")
show(io::IO, ::Type{CSE{CS,E}}) where {S,T,CS<:CharSet{S},E<:Encoding{T}} =
    print(io, "CSE{", string(S), ", ", string(T), "}")

# Note: this is still in transition to expressing character set, encoding
# and optional cached info for hashes, UTF-8/UTF-16 encodings, subsets, etc.
# via more type parameters

const STR_DATA_TYPE = STR_DATA_VECTOR ? Vector{UInt8} : String

struct Str{T,SubStr,Cache,Hash} <: AbstractString
    data::STR_DATA_TYPE
    substr::SubStr
    cache::Cache
    hash::Hash

    ((::Type{Str})(::CSE_T, v::STR_DATA_TYPE)
        where {CSE_T<:CSE} =
      new{CSE_T,Nothing,Nothing,Nothing}(v,nothing,nothing,nothing))
    ((::Type{Str})(::Type{CSE_T}, v::STR_DATA_TYPE)
        where {CSE_T<:CSE} =
      new{CSE_T,Nothing,Nothing,Nothing}(v,nothing,nothing,nothing))
end

# Handle change from endof -> lastindex
@static if !isdefined(Base, :lastindex)
    export lastindex
    lastindex(str::AbstractString) = Base.endof(str)
    lastindex(arr::AbstractArray) = Base.endof(arr)
    Base.endof(str::Str) = lastindex(str)
end
@static if !isdefined(Base, :firstindex)
    export firstindex
    firstindex(str::AbstractString) = 1
    # AbstractVector might be an OffsetArray
    firstindex(str::Vector) = 1
end

# This needs to be redone, with character sets and the code unit as part of the type

const CodeUnitTypes = Union{UInt8, UInt16, UInt32}

abstract type CodePoint <: AbstractChar end

const _cpname1 = [:Text1, :ASCII, :Latin]
const _cpname2 = [:Text2, :UCS2]
const _cpname4 = [:Text4, :UTF32]
const _subsetnam = [:_Latin, :_UCS2, :_UTF32]
const _mbwname   = [:UTF8, :UTF16] # Multi-byte/word

for (names, siz) in ((_cpname1, 8), (_cpname2, 16), (_cpname4, 32)), nam in names
    chrnam = symstr(nam, "Chr")
    @eval primitive type $chrnam <: CodePoint $siz end
    @eval export $chrnam
end
primitive type _LatinChr <: CodePoint 8 end

for nam in charsets
    @eval charset(::Type{$(symstr(nam, "Chr"))}) = $(symstr(nam, "CharSet"))
end
charset(::Type{Char}) = UniPlusCharSet

const CodePointTypes = Union{CodeUnitTypes, CodePoint}

const LatinChars   = Union{LatinChr, _LatinChr}
const ByteChars    = Union{ASCIIChr, LatinChr, _LatinChr, Text1Chr}
const WideChars    = Union{UCS2Chr, UTF32Chr}
const UnicodeChars = Union{ASCIIChr, LatinChars, UCS2Chr, UTF32Chr}

export UnicodeChars

const BuiltInTypes = vcat(_cpname1, _cpname2, _cpname4, _subsetnam, _mbwname)

const BinaryCSE = CSE{BinaryCharSet,  Native1Byte}

const _encnam1 = [:Text1, :Binary, :ASCII, :Latin]

for (cs, enc) in ((Native1Byte, _encnam1), (Native2Byte, _cpname2), (Native4Byte, _cpname4)),
    nam in enc
    @eval const $(symstr(nam, "CSE")) = CSE{$(symstr(nam, "CharSet")), $cs}
end
const UTF8CSE   = CSE{UTF32CharSet, NativeUTF8}
const UTF16CSE  = CSE{UTF32CharSet, NativeUTF16}

const _LatinCSE = CSE{LatinSubSet,  Native1Byte}
const _UCS2CSE  = CSE{UCS2SubSet,   Native2Byte}
const _UTF32CSE = CSE{UTF32SubSet,  Native4Byte}

for nam in BuiltInTypes
    sym = Symbol("$(nam)Str")
    cse = Symbol("$(nam)CSE")
    @eval const $sym = Str{$cse, Nothing, Nothing, Nothing}
    @eval show(io::IO, ::Type{$sym}) = print(io, $(quotesym(sym)))
    @eval show(io::IO, ::Type{$cse}) = print(io, $(quotesym(cse)))
end
show(io::IO, ::Type{BinaryCSE}) = print(io, "BinaryCSE")

for nam in (:ASCII, :Latin, :_Latin, :UCS2, :UTF32, :Text1, :Text2, :Text4)
    @eval codepoint_cse(::Type{$(Symbol("$(nam)Chr"))}) = $(Symbol("$(nam)CSE"))
end

"""Union type for fast dispatching"""
const UniStr = Union{ASCIIStr, _LatinStr, _UCS2Str, _UTF32Str}
show(io::IO, ::Type{UniStr}) = print(io, :UniStr)

if STR_DATA_VECTOR
    _allocate(len) = create_vector(UInt8, len)
else
    _allocate(len) = Base._string_n((len+STR_KEEP_NUL-1)%Csize_t)
end

function _allocate(::Type{T}, len) where {T <: CodeUnitTypes}
    buf = _allocate((len+STR_KEEP_NUL-1) * sizeof(T))
    buf, reinterpret(Ptr{T}, pointer(buf))
end

const list = [(:ASCII, :ascii), (:Latin, :latin), (:UCS2,  :ucs2), (:UTF32, :utf32),
              (:UTF8,  :utf8), (:UTF16, :utf16), (:Binary, :binary)]
const sublist = [(:_Latin, :_latin), (:_UCS2, :_ucs2), (:_UTF32, :_utf32)]

const empty_string = ""
if STR_DATA_VECTOR
    const empty_strvec = _allocate(0)
else
    const empty_strvec = empty_string
end
empty_str(::Type{String}) = empty_string

for (nam, low) in vcat(list, sublist)
    sym = symstr(nam, "Str")
    @eval const $sym = Str{$(symstr(nam, "CSE")), Nothing,  Nothing, Nothing}
    @eval const $(symstr("empty_", low)) = Str($(symstr(nam, "CSE")), empty_strvec)
    @eval const empty_str(::Type{$sym}) = $(symstr("empty_", low))
    @eval (::Type{$sym})(v::Vector{UInt8}) = convert($sym, v)
end
for val in list ; @eval export $(symstr(val[1], "Str")) ; end

@inline function _convert(::Type{T}, a::Vector{UInt8}) where {T<:Str}
    if STR_DATA_VECTOR
        Str(cse(T), copyto!(_allocate(sizeof(a)), a))
    else
        siz = sizeof(a)
        buf = _allocate(siz)
        unsafe_copyto!(pointer(buf), pointer(a), siz)
        Str(cse(T), buf)
    end
end

# Various useful groups of character set types

# These should be done via traits
const Binary_CSEs   = Union{Text1CSE, BinaryCSE}
const Raw_CSEs      = Union{Text1CSE, Text2CSE, Text4CSE}
const Latin_CSEs    = Union{LatinCSE, _LatinCSE}
const UCS2_CSEs     = Union{UCS2CSE,  _UCS2CSE}
const UTF32_CSEs    = Union{UTF32CSE, _UTF32CSE}
const Unicode_CSEs  = Union{UTF8CSE, UTF16CSE, UTF32_CSEs}
const SubSet_CSEs   = Union{_LatinCSE, _UCS2CSE, _UTF32CSE}

const Byte_CSEs     = Union{ASCIICSE, Binary_CSEs, Latin_CSEs, UTF8CSE}
const Word_CSEs     = Union{Text2CSE, UCS2_CSEs, UTF16CSE} # 16-bit characters
const Quad_CSEs     = Union{Text4CSE, UTF32_CSEs}          # 32-bit code units
const Wide_CSEs     = Union{UTF16CSE, UCS2_CSEs, UTF32_CSEs}
const WordQuad_CSEs = Union{Text2CSE,Text4CSE,UCS2CSE,UTF16CSE,UTF32CSE}

const BinaryStrings = Str{BinaryCSE}
const ASCIIStrings = Str{ASCIICSE}
const RawStrings   = Str{<:Raw_CSEs}
const LatinStrings = Str{<:Latin_CSEs}
const UCS2Strings  = Str{<:UCS2_CSEs}
const UTF32Strings = Str{<:UTF32_CSEs}

const ByteStr = Str{<:Byte_CSEs}
const WordStr = Str{<:Word_CSEs}
const QuadStr = Str{<:Quad_CSEs}
const WideStr = Str{<:Wide_CSEs}

const UnicodeByteStrings = Union{Str{ASCIICSE}, LatinStrings}
const UnicodeStrings     = Union{String, Str{<:Unicode_CSEs}}

const AbsChar = @static isdefined(Base, :AbstractChar) ? AbstractChar : Union{Char, CodePoint}
const ByteStrings  = Union{String, ByteStr}

## Get the character set / encoding used by a string type
cse(::Type{<:AbstractString}) = UTF8CSE # Default unless overridden
cse(::Type{<:Str{C}}) where {C<:CSE} = C
cse(str::AbstractString) = cse(typeof(str))

charset(::Type{<:AbstractString}) = UniPlusCharSet # Default unless overridden
charset(::Type{<:Str{CSE{CS}}}) where {CS} = CS
charset(str::AbstractString) = charset(typeof(str))

encoding(::Type{<:AbstractString}) = UTF8Encoding # Julia likes to think of this as the default
encoding(::Type{<:Str{CSE{CS,E}}}) where {CS,E} = E
encoding(str::AbstractString) = encoding(typeof(str))

promote_rule(::Type{T}, ::Type{T}) where {T<:CodePoint} = T
promote_rule(::Type{Text2Chr}, ::Type{Text1Chr}) = Text2Chr
promote_rule(::Type{Text4Chr}, ::Type{Text1Chr}) = Text4Chr
promote_rule(::Type{Text4Chr}, ::Type{Text2Chr}) = Text4Chr

promote_rule(::Type{T}, ::Type{ASCIIChr}) where {T} = T
promote_rule(::Type{LatinChr}, ::Type{_LatinChr}) = LatinChr
promote_rule(::Type{UTF32Chr}, ::Type{UCS2Chr}) = UTF32Chr
promote_rule(::Type{T}, ::Type{<:ByteChars}) where {T<:WideChars} = T

promote_rule(::Type{T}, ::Type{T}) where {T<:Str} = T
promote_rule(::Type{T}, ::Type{<:Str{Text1CSE}}) where {T<:Str{Text2CSE}} = T
promote_rule(::Type{T}, ::Type{<:Str{Text1CSE}}) where {T<:Str{Text4CSE}} = T
promote_rule(::Type{T}, ::Type{<:Str{Text2CSE}}) where {T<:Str{Text4CSE}} = T

promote_rule(::Type{T}, ::Type{<:Str{ASCIICSE}}) where {T<:Union{LatinStrings,UnicodeStrings,WideStr}} = T
promote_rule(::Type{T}, ::Type{<:LatinStrings}) where {T<:Union{UnicodeStrings,WideStr}} = T
promote_rule(::Type{T}, ::Type{<:UCS2Strings})  where {T<:Union{UTF32Strings}} = T

promote_rule(::Type{T}, ::Type{<:Str{_LatinCSE}}) where {T<:Str{LatinCSE}} = T
promote_rule(::Type{T}, ::Type{<:Str{_UCS2CSE}})  where {T<:Str{UCS2CSE}} = T
promote_rule(::Type{T}, ::Type{<:Str{_UTF32CSE}}) where {T<:Str{UTF32CSE}} = T

sizeof(s::Str) = sizeof(s.data) + !STR_DATA_VECTOR - STR_KEEP_NUL

"""Codeunits of string as a Vector"""
_data(s::Vector{UInt8}) = s
if STR_DATA_VECTOR
    _data(s::String)  =
        @static VERSION < v"0.7.0-DEV" ? Vector{UInt8}(s) : unsafe_wrap(Vector{UInt8}, s)
    _data(s::ByteStr) = s.data
else
    _data(s::String)  = s
    _data(s::ByteStr) =
        @static VERSION < v"0.7.0-DEV" ? Vector{UInt8}(s.data) : unsafe_wrap(Vector{UInt8}, s.data)
end

"""Pointer to codeunits of string"""
_pnt(s::Union{String,Vector{UInt8}}) = pointer(s)
_pnt(s::ByteStr) = pointer(s.data)
_pnt(s::WordStr) = reinterpret(Ptr{UInt16}, pointer(s.data))
_pnt(s::QuadStr) = reinterpret(Ptr{UInt32}, pointer(s.data))

const CHUNKSZ = sizeof(UInt64) # used for fast processing of strings

_pnt64(s::Union{String,Vector{UInt8}}) = reinterpret(Ptr{UInt64}, pointer(s))
_pnt64(s::Str) = reinterpret(Ptr{UInt64}, pointer(s.data))

"""Length of string in codeunits"""
_len(s) = sizeof(s)
_len(s::WordStr) = sizeof(s) >>> 1
_len(s::QuadStr) = sizeof(s) >>> 2

# For convenience
@inline _lenpnt(s) = _len(s), _pnt(s)

@inline _calcpnt(str, siz) = (pnt = _pnt64(str) - CHUNKSZ;  (pnt, pnt + siz))

@inline _mask_bytes(n) = (1%UInt << ((n & (CHUNKSZ - 1)) << 3)) - 0x1

Base.need_full_hex(c::CodePoint) = isxdigit(c)
Base.escape_nul(c::CodePoint) = ('0' <= c <= '7') ? "\\x00" : "\\0"
