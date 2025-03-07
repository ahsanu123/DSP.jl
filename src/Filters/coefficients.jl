# Filter types and conversions

using Base: uabs

abstract type FilterCoefficients{Domain} end

Base.convert(::Type{T}, f::FilterCoefficients) where {T<:FilterCoefficients} = T(f)


#
# Zero-pole gain form
#

"""
    ZeroPoleGain(z::Vector, p::Vector, k::Number)

Filter representation in terms of zeros `z`, poles `p`, and
gain `k`:
```math
H(x) = k\\frac{(x - \\verb!z[1]!) \\ldots (x - \\verb!z[m]!)}{(x - \\verb!p[1]!) \\ldots (x - \\verb!p[n]!)}
```
"""
struct ZeroPoleGain{Domain,Z<:Number,P<:Number,K<:Number} <: FilterCoefficients{Domain}
    z::Vector{Z}
    p::Vector{P}
    k::K
end

ZeroPoleGain(f::FilterCoefficients{D}) where {D} = ZeroPoleGain{D}(f)
ZeroPoleGain(z::Vector, p::Vector, k) = ZeroPoleGain{:z}(z, p, k)
ZeroPoleGain{D,Z,P,K}(f::ZeroPoleGain) where {D,Z,P,K} = ZeroPoleGain{D,Z,P,K}(f.z, f.p, f.k)
ZeroPoleGain{D}(f::ZeroPoleGain{D,Z,P,K}) where {D,Z,P,K} = ZeroPoleGain{D,Z,P,K}(f)
ZeroPoleGain{D}(z::Vector{Z}, p::Vector{P}, k::K) where {D,Z<:Number,P<:Number,K<:Number} =
    ZeroPoleGain{D,Z,P,K}(z, p, k)

Base.promote_rule(::Type{ZeroPoleGain{D,Z1,P1,K1}}, ::Type{ZeroPoleGain{D,Z2,P2,K2}}) where {D,Z1,P1,K1,Z2,P2,K2} =
    ZeroPoleGain{D,promote_type(Z1,Z2),promote_type(P1,P2),promote_type(K1,K2)}

*(f::ZeroPoleGain{D}, g::Number) where {D} = ZeroPoleGain{D}(f.z, f.p, f.k * g)
*(g::Number, f::ZeroPoleGain{D}) where {D} = ZeroPoleGain{D}(f.z, f.p, f.k * g)
*(f1::ZeroPoleGain{D}, f2::ZeroPoleGain{D}) where {D} =
    ZeroPoleGain{D}([f1.z; f2.z], [f1.p; f2.p], f1.k * f2.k)
*(f1::ZeroPoleGain{D}, fs::ZeroPoleGain{D}...) where {D} =
    ZeroPoleGain{D}(vcat(f1.z, map(f -> f.z, fs)...), vcat(f1.p, map(f -> f.p, fs)...),
        f1.k * prod(f.k for f in fs))

Base.inv(f::ZeroPoleGain{D}) where {D} = ZeroPoleGain{D}(f.p, f.z, inv(f.k))

function Base.:^(f::ZeroPoleGain{D}, e::Integer) where {D}
    ae = uabs(e)
    z, p = repeat(f.z, ae), repeat(f.p, ae)
    return e < 0 ? ZeroPoleGain{D}(p, z, inv(f.k)^ae) : ZeroPoleGain{D}(z, p, f.k^ae)
end

#
# Transfer function form
#

function shiftpoly(p::LaurentPolynomial{T,D}, i::Integer) where {T<:Number,D}
    if !iszero(i)
        return p * LaurentPolynomial{T,D}([one(T)], i)
    end
    return p
end

struct PolynomialRatio{Domain,T<:Number} <: FilterCoefficients{Domain}
    b::LaurentPolynomial{T,Domain}
    a::LaurentPolynomial{T,Domain}

    function PolynomialRatio{:z,Ti}(b::LaurentPolynomial, a::LaurentPolynomial) where {Ti<:Number}
        i = max(lastindex(a), lastindex(b))
        b = shiftpoly(b, -i)
        a = shiftpoly(a, -i)
        if !isone(a[0])
            if iszero(a[0])
                throw(ArgumentError("filter must have non-zero leading denominator coefficient"))
            end
            b /= a[0]
            a /= a[0]
        end
        return new{:z,Ti}(b, a)
    end
    function PolynomialRatio{:s,Ti}(b::LaurentPolynomial, a::LaurentPolynomial) where {Ti<:Number}
        if iszero(a)
            throw(ArgumentError("filter must have non-zero denominator"))
        end
        i = min(firstindex(a), firstindex(b))
        b = shiftpoly(b, -i)
        a = shiftpoly(a, -i)
        return new{:s,Ti}(b, a)
    end
end
PolynomialRatio(f::FilterCoefficients{D}) where {D} = PolynomialRatio{D}(f)
"""
    PolynomialRatio(b::Union{Number, Vector{<:Number}}, a::Union{Number, Vector{<:Number}})

Filter representation in terms of the coefficients of the numerator
`b` and denominator `a` in the z or s domain
where `b` and `a` are vectors ordered from highest power to lowest.\n
Inputs that are `Number`s are treated as one-element `Vector`s.\n
Filter with:
- Transfer function in z domain (zero & negative z powers):
```math
H(z) = \\frac{\\verb!b[1]! + \\ldots + \\verb!b[m]! z^{-m+1}}{\\verb!a[1]! + \\ldots + \\verb!a[n]! z^{-n+1}}
```
returns `PolynomialRatio` object with `a[1] = 1` and other specified coefficients divided by `a[1]`.
```jldoctest
julia> PolynomialRatio([1,1],[1,2])
PolynomialRatio{:z, Float64}(LaurentPolynomial(1.0*z⁻¹ + 1.0), LaurentPolynomial(2.0*z⁻¹ + 1.0))
julia> PolynomialRatio{:z}([1,2,3],[2,3,4])
PolynomialRatio{:z, Float64}(LaurentPolynomial(1.5*z⁻² + 1.0*z⁻¹ + 0.5), LaurentPolynomial(2.0*z⁻² + 1.5*z⁻¹ + 1.0))
```
- Transfer function in s domain (zero & positive s powers):
```math
H(s) = \\frac{\\verb!b[1]! s^{m-1} + \\ldots + \\verb!b[m]!}{\\verb!a[1]! s^{n-1} + \\ldots + \\verb!a[n]!}
```
returns `PolynomialRatio` object with specified `b` and `a` coefficients.
```jldoctest
julia> PolynomialRatio{:s}([1,2,3],[2,3,4])
PolynomialRatio{:s, Int64}(LaurentPolynomial(3 + 2*s + s²), LaurentPolynomial(4 + 3*s + 2*s²))
```

"""
PolynomialRatio(b, a) = PolynomialRatio{:z}(b, a)
const PolynomialRatioArgTs{T} = Union{T,Vector{T},LaurentPolynomial{T}} where {T<:Number}
PolynomialRatio{:z}(b::PolynomialRatioArgTs{T1}, a::PolynomialRatioArgTs{T2}) where {T1<:Number,T2<:Number} =
    PolynomialRatio{:z,typeof(one(T1) / one(T2))}(b, a)
PolynomialRatio{:s}(b::PolynomialRatioArgTs{T1}, a::PolynomialRatioArgTs{T2}) where {T1<:Number,T2<:Number} =
    PolynomialRatio{:s,promote_type(T1, T2)}(b, a)

"""
    _polyprep(D::Symbol, x::Union{T,Vector{T}}, ::Type) where {T<:Number}

Converts `x` to polynomial form. If x is a `Number`, it has to be converted into
a `Vector`, otherwise `LaurentPolynomial` dispatch goes into stack overflow
trying to collect a 0-d array into a `Vector`.

!!! warning

    The DSP convention for Laplace domain is highest power first.\n
    The Polynomials.jl convention is lowest power first.
"""
@inline _polyprep(D::Symbol, x::Union{T,Vector{T}}, ::Type{V}) where {T<:Number,V} =
    LaurentPolynomial{V,D}(x isa Vector ? reverse(x) : [x], D === :z ? -length(x) + 1 : 0)

function PolynomialRatio{:z,T}(b::Union{Number,Vector{<:Number}}, a::Union{Number,Vector{<:Number}}) where {T<:Number}
    if isempty(a) || iszero(a[1])
        throw(ArgumentError("filter must have non-zero leading denominator coefficient"))
    end
    return PolynomialRatio{:z,T}(_polyprep(:z, b / a[1], T), _polyprep(:z, a / a[1], T))
end
PolynomialRatio{:s,T}(b::Union{Number,Vector{<:Number}}, a::Union{Number,Vector{<:Number}}) where {T<:Number} =
    PolynomialRatio{:s,T}(_polyprep(:s, b, T), _polyprep(:s, a, T))

PolynomialRatio{D,T}(f::PolynomialRatio{D}) where {D,T} = PolynomialRatio{D,T}(f.b, f.a)
PolynomialRatio{D}(f::PolynomialRatio{D,T}) where {D,T} = PolynomialRatio{D,T}(f)

Base.promote_rule(::Type{PolynomialRatio{D,T}}, ::Type{PolynomialRatio{D,S}}) where {D,T,S} = PolynomialRatio{D,promote_type(T,S)}

function PolynomialRatio{D,T}(f::ZeroPoleGain{D}) where {D,T<:Real}
    b = convert(LaurentPolynomial{T}, real(f.k * fromroots(f.z; var=D)))
    a = convert(LaurentPolynomial{T}, real(fromroots(f.p; var=D)))
    return PolynomialRatio{D,T}(b, a)
end
PolynomialRatio{D}(f::ZeroPoleGain{D,Z,P,K}) where {D,Z,P,K} =
    PolynomialRatio{D,promote_type(real(Z),real(P),K)}(f)

ZeroPoleGain{D,Z,P,K}(f::PolynomialRatio{D}) where {D,Z,P,K} =
    ZeroPoleGain{D,Z,P,K}(ZeroPoleGain{D}(f))
function ZeroPoleGain{D}(f::PolynomialRatio{D,T}) where {D,T}
    i = -min(firstindex(f.a), firstindex(f.b), 0)
    z = roots(shiftpoly(f.b, i))
    p = roots(shiftpoly(f.a, i))
    return ZeroPoleGain{D}(z, p, f.b[end]/f.a[end])
end

*(f::PolynomialRatio{D}, g::Number) where {D} = PolynomialRatio{D}(g * f.b, f.a)
*(g::Number, f::PolynomialRatio{D}) where {D} = PolynomialRatio{D}(g * f.b, f.a)
*(f1::PolynomialRatio{D}, f2::PolynomialRatio{D}) where {D} =
    PolynomialRatio{D}(f1.b * f2.b, f1.a * f2.a)
*(f1::PolynomialRatio{D}, fs::PolynomialRatio{D}...) where {D} =
    PolynomialRatio{D}(f1.b * prod(f.b for f in fs), f1.a * prod(f.a for f in fs))

Base.inv(f::PolynomialRatio{D}) where {D} = PolynomialRatio{D}(f.a, f.b)

function Base.:^(f::PolynomialRatio{D,T}, e::Integer) where {D,T}
    ae = uabs(e)
    b, a = f.b^ae, f.a^ae
    if e < 0
        b, a = a, b
    end
    return PolynomialRatio{D}(b, a)
end

coef_s(p::LaurentPolynomial) = p[end:-1:0]
coef_z(p::LaurentPolynomial) = p[0:-1:begin]

"""
    coefb(f::PolynomialRatio)

Coefficients of the numerator of a `PolynomialRatio` object, highest power
first, i.e., the `b` passed to `filt()`
"""
coefb(f::PolynomialRatio{:s}) = coef_s(f.b)
coefb(f::PolynomialRatio{:z}) = coef_z(f.b)
coefb(f::FilterCoefficients) = coefb(PolynomialRatio(f))

"""
    coefa(f::PolynomialRatio)

Coefficients of the denominator of a `PolynomialRatio` object, highest power
first, i.e., the `a` passed to `filt()`
"""
coefa(f::PolynomialRatio{:s}) = coef_s(f.a)
coefa(f::PolynomialRatio{:z}) = coef_z(f.a)
coefa(f::FilterCoefficients) = coefa(PolynomialRatio(f))

#
# Biquad filter in transfer function form
# A separate immutable to improve efficiency of filtering using SecondOrderSections
#
"""
    Biquad(b0::T, b1::T, b2::T, a1::T, a2::T) where T <: Number

Filter representation in terms of the transfer function of a single
second-order section given by:
```math
H(s) = \\frac{\\verb!b0! s^2+\\verb!b1! s+\\verb!b2!}{s^2+\\verb!a1! s + \\verb!a2!}
```
or equivalently:
```math
H(z) = \\frac{\\verb!b0!+\\verb!b1! z^{-1}+\\verb!b2! z^{-2}}{1+\\verb!a1! z^{-1} + \\verb!a2! z^{-2}}
```
"""
struct Biquad{Domain,T<:Number} <: FilterCoefficients{Domain}
    b0::T
    b1::T
    b2::T
    a1::T
    a2::T
end
Biquad(f::FilterCoefficients{D}) where {D} = Biquad{D}(f)
Biquad(args...) = Biquad{:z}(args...)
Biquad{D}(b0::T, b1::T, b2::T, a1::T, a2::T) where {D,T} =
    Biquad{D,T}(b0, b1, b2, a1, a2)
Biquad{D}(b0::T, b1::T, b2::T, a0::T, a1::T, a2::T, g::Number=1) where {D,T} =
    (x = g*b0/a0; Biquad{D,typeof(x)}(x, g*b1/a0, g*b2/a0, a1/a0, a2/a0))

Biquad{D,T}(f::Biquad{D}) where {D,T} = Biquad{D,T}(f.b0, f.b1, f.b2, f.a1, f.a2)

Base.promote_rule(::Type{Biquad{D,T}}, ::Type{Biquad{D,S}}) where {D,T,S} = Biquad{D,promote_type(T,S)}

ZeroPoleGain{D,Z,P,K}(f::Biquad{D}) where {D,Z,P,K} = ZeroPoleGain{D,Z,P,K}(PolynomialRatio{D}(f))
ZeroPoleGain{D}(f::Biquad) where {D} = ZeroPoleGain{D}(convert(PolynomialRatio{D}, f))

function PolynomialRatio{D,T}(f::Biquad{D}) where {D,T}
    b = T[f.b0, f.b1, f.b2]
    a = T[one(T), f.a1, f.a2]
    PolynomialRatio{D,T}(b, a)
end
PolynomialRatio{D}(f::Biquad{D,T}) where {D,T} = PolynomialRatio{D,T}(f)

function Biquad{D,T}(f::PolynomialRatio{D}) where {D,T}
    a, b = f.a, f.b
    lastidx = max(lastindex(b), lastindex(a))

    if lastidx - min(firstindex(b), firstindex(a)) >= 3
        throw(ArgumentError("cannot convert a filter of length > 3 to Biquad"))
    end
    if !isone(a[lastidx])
        throw(ArgumentError("leading denominator coefficient of a Biquad must be one"))
    end
    Biquad{D,T}(b[lastidx], b[lastidx-1], b[lastidx-2], a[lastidx-1], a[lastidx-2])
end
Biquad{D}(f::PolynomialRatio{D,T}) where {D,T} = Biquad{D,T}(f)

Biquad{D,T}(f::ZeroPoleGain{D}) where {D,T} = Biquad{D,T}(convert(PolynomialRatio, f))
Biquad{D}(f::ZeroPoleGain{D}) where {D} = Biquad{D}(convert(PolynomialRatio, f))

*(f::Biquad{D}, g::Number) where {D} = Biquad{D}(f.b0*g, f.b1*g, f.b2*g, f.a1, f.a2)
*(g::Number, f::Biquad{D}) where {D} = Biquad{D}(f.b0*g, f.b1*g, f.b2*g, f.a1, f.a2)

Base.inv(f::Biquad{D,T}) where {D,T} = Biquad{D}(one(T), f.a1, f.a2, f.b0, f.b1, f.b2)

#
# Second-order sections (array of biquads)
#
"""
    SecondOrderSections(biquads::Vector{<:Biquad}, gain::Number)

Filter representation in terms of a cascade of second-order
sections and gain. `biquads` must be specified as a vector of
`Biquads`.
"""
struct SecondOrderSections{Domain,T<:Number,G<:Number} <: FilterCoefficients{Domain}
    biquads::Vector{Biquad{Domain,T}}
    g::G
end
SecondOrderSections(f::FilterCoefficients{D}) where {D} = SecondOrderSections{D}(f)
SecondOrderSections{D}(biquads::Vector{Biquad{D,T}}, g::G) where {D,T,G} =
    SecondOrderSections{D,T,G}(biquads, g)

Base.promote_rule(::Type{SecondOrderSections{D,T1,G1}}, ::Type{SecondOrderSections{D,T2,G2}}) where {D,T1,G1,T2,G2} =
    SecondOrderSections{D,promote_type(T1,T2),promote_type(G1,G2)}

SecondOrderSections{D,T,G}(f::SecondOrderSections) where {D,T,G} =
    SecondOrderSections{D,T,G}(f.biquads, f.g)
SecondOrderSections{D,T,G}(f::Biquad{D}) where {D,T,G} = SecondOrderSections{D,T,G}([f], one(G))

SecondOrderSections{D}(f::SecondOrderSections{D,T,G}) where {D,T,G} = SecondOrderSections{D,T,G}(f)
SecondOrderSections{D}(f::Biquad{D,T}) where {D,T} = SecondOrderSections{D,T,Int}(f)

*(f::SecondOrderSections{D}, g::Number) where {D} = SecondOrderSections{D}(f.biquads, f.g * g)
*(g::Number, f::SecondOrderSections{D}) where {D} = SecondOrderSections{D}(f.biquads, f.g * g)
*(f1::SecondOrderSections{D}, f2::SecondOrderSections{D}) where {D} =
    SecondOrderSections{D}([f1.biquads; f2.biquads], f1.g * f2.g)
*(f1::SecondOrderSections{D}, fs::SecondOrderSections{D}...) where {D} =
    SecondOrderSections{D}(vcat(f1.biquads, map(f -> f.biquads, fs)...), f1.g * prod(f.g for f in fs))

*(f1::Biquad{D}, f2::Biquad{D}) where {D} = SecondOrderSections{D}([f1, f2], 1)
*(f1::Biquad{D}, fs::Biquad{D}...) where {D} = SecondOrderSections{D}([f1, fs...], 1)
*(f1::SecondOrderSections{D}, f2::Biquad{D}) where {D} =
    SecondOrderSections{D}([f1.biquads; f2], f1.g)
*(f1::Biquad{D}, f2::SecondOrderSections{D}) where {D} =
    SecondOrderSections{D}([f1; f2.biquads], f2.g)

Base.inv(f::SecondOrderSections{D}) where {D} = SecondOrderSections{D}(inv.(f.biquads), inv(f.g))

function Base.:^(f::SecondOrderSections{D}, e::Integer) where {D}
    ae = uabs(e)
    if e < 0
        inv_f = inv(f)
        return SecondOrderSections{D}(repeat(inv_f.biquads, ae), inv_f.g^ae)
    else
        return SecondOrderSections{D}(repeat(f.biquads, ae), f.g^ae)
    end
end

function Base.:^(f::Biquad{D}, e::Integer) where {D}
    ae = uabs(e)
    return SecondOrderSections{D}(fill(e < 0 ? inv(f) : f, ae), 1)
end

function Biquad{D,T}(f::SecondOrderSections{D}) where {D,T}
    if length(f.biquads) != 1
        throw(ArgumentError("only a single second order section may be converted to a biquad"))
    end
    Biquad{D,T}(f.biquads[1] * f.g)
end
Biquad{D}(f::SecondOrderSections{D,T,G}) where {D,T,G} = Biquad{D,promote_type(T, G)}(f)

function ZeroPoleGain{D,Z,P,K}(f::SecondOrderSections{D}) where {D,Z,P,K}
    z = Z[]
    p = P[]
    k = f.g
    for biquad in f.biquads
        biquadzpk = ZeroPoleGain{D}(biquad)
        append!(z, biquadzpk.z)
        append!(p, biquadzpk.p)
        k *= biquadzpk.k
    end
    ZeroPoleGain{D,Z,P,K}(z, p, k)
end
ZeroPoleGain{D}(f::SecondOrderSections{D,T,G}) where {D,T,G} =
    ZeroPoleGain{D,complex(T),complex(T),G}(f)

PolynomialRatio{D,T}(f::SecondOrderSections{D}) where {D,T} = PolynomialRatio{D,T}(ZeroPoleGain(f))
PolynomialRatio{D}(f::SecondOrderSections{D}) where {D} = PolynomialRatio{D}(ZeroPoleGain(f))

# Group each pole in p with its closest zero in z
# Remove paired poles from p and z
function groupzp(z, p)
    n = min(length(z), length(p))
    groupedz = similar(z, n)
    i = 1
    while i <= n
        p_i = p[i]
        _, closest_zero_idx = findmin(x -> abs(x - p_i), z)
        groupedz[i] = splice!(z, closest_zero_idx)
        if !isreal(groupedz[i])
            i += 1
            groupedz[i] = splice!(z, closest_zero_idx)
        end
        i += 1
    end
    return (groupedz, splice!(p, 1:n))
end

# Sort zeros or poles lexicographically (so that poles are adjacent to
# their conjugates). Handle repeated values. Split real and complex
# values into separate vectors. Ensure that each value has a conjugate.
function split_real_complex(x::Vector{T}; sortby=nothing) where T
    # Get counts and store in a Dict
    d = Dict{T,Int}()
    for v in x
        # needs to be in normal form since 0.0 !== -0.0
        tonormal(x) = x == 0 ? abs(x) : x
        vn = complex(tonormal(real(v)), tonormal(imag(v)))
        d[vn] = get(d, vn, 0)+1
    end

    c = T[]
    r = real(T)[]
    ks = collect(keys(d))
    if sortby !== nothing
        sort!(ks; by=sortby)
    end
    for k in ks
        if imag(k) != 0
            if !haskey(d, conj(k)) || d[k] != d[conj(k)]
                # No match for conjugate
                return (c, r, false)
            elseif imag(k) > 0
                # Add key and its conjugate
                for n = 1:d[k]
                    push!(c, k, conj(k))
                end
            end
        else
            for n = 1:d[k]
                push!(r, k)
            end
        end
    end
    return (c, r, true)
end

# Convert a filter to second-order sections
# The returned sections are in ZPK form
function SecondOrderSections{D,T,G}(f::ZeroPoleGain{D,Z,P}) where {D,T,G,Z,P}
    z = f.z
    p = f.p
    nz = length(z)
    n = length(p)
    nz > n && throw(ArgumentError("ZeroPoleGain must not have more zeros than poles"))

    # Split real and complex poles
    (complexz, realz, matched) = split_real_complex(z)
    matched || throw(ArgumentError("complex zeros could not be matched to their conjugates"))
    (complexp, realp, matched) = split_real_complex(p; sortby=x->abs(abs(x) - 1))
    matched || throw(ArgumentError("complex poles could not be matched to their conjugates"))

    # Group complex poles with closest complex zeros
    z1, p1 = groupzp(complexz, complexp)
    # Group real poles with remaining complex zeros
    z2, p2 = groupzp(complexz, realp)
    # Group remaining complex poles with closest real zeros
    z3, p3 = groupzp(realz, complexp)
    # Group remaining real poles with closest real zeros
    z4, p4 = groupzp(realz, realp)

    # All zeros are now paired with a pole, but not all poles are
    # necessarily paired with a zero
    @assert isempty(complexz)
    @assert isempty(realz)
    groupedz = [z1; z2; z3; z4]::Vector{Z}
    groupedp = [p1; p2; p3; p4; complexp; realp]::Vector{P}
    @assert length(groupedz) == nz
    @assert length(groupedp) == n

    # Allocate memory for biquads
    biquads = Vector{Biquad{D,T}}(undef, (n >> 1)+(n & 1))

    # Build second-order sections in reverse
    # First do complete pairs
    npairs = length(groupedp) >> 1
    odd = isodd(n)
    for i = 1:npairs
        pairidx = 2 * (npairs - i)
        biquads[odd+i] = convert(Biquad, ZeroPoleGain{D}(groupedz[pairidx+1:min(pairidx+2, length(groupedz))],
                                                         groupedp[pairidx+1:pairidx+2], one(T)))
    end

    if odd
        # Now do remaining pole and (maybe) zero
        biquads[1] = convert(Biquad, ZeroPoleGain{D}(groupedz[length(groupedp):end],
                                                     [groupedp[end]], one(T)))
    end

    SecondOrderSections{D,T,G}(biquads, f.k)
end
SecondOrderSections{D}(f::ZeroPoleGain{D,Z,P,K}) where {D,Z,P,K} =
    SecondOrderSections{D,promote_type(real(Z), real(P)), K}(f)

SecondOrderSections{D}(f::FilterCoefficients{D}) where {D} = SecondOrderSections{D}(ZeroPoleGain(f))
