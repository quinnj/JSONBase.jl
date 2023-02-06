struct ToStructClosure{T}
    vec::Vector{Any}
end

function (f::ToStructClosure{T})(key, val) where {T}
    Base.@nexprs 32 i -> begin
        k_i = fieldname(T, i)
        if Selectors.eq(k_i, tostring(key))
            _togeneric(val, x -> f.vec[i] = x)
            return API.Continue()
        end
    end
    error("error")
end

function tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T}
    N = fieldcount(T)
    vec = Vector{Any}(undef, N)
    c = ToStructClosure{T}(vec)
    pos = parseobject(x, c)
    return T(vec...)
end
