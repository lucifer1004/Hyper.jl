struct Headers
    headers_internal::Ptr{HeadersInternal}
end

function Base.setproperty!(headers::Headers, key::Symbol, value)
    key_bytes = Vector{UInt8}(String(key))
    value_bytes = Vector{UInt8}(value)

    ccall(
        (:hyper_headers_set, libhyper),
        Cvoid,
        (Ptr{HeadersInternal}, Ptr{UInt8}, UInt, Ptr{UInt8}, UInt),
        headers.headers_internal,
        key_bytes,
        UInt(length(key_bytes)),
        value_bytes,
        UInt(length(value_bytes)),
    )
end

function Base.push!(headers::Headers, kv::Pair)
    key_bytes = Vector{UInt8}(kv.first)
    value_bytes = Vector{UInt8}(kv.second)

    ccall(
        (:hyper_headers_add, libhyper),
        Cvoid,
        (Ptr{HeadersInternal}, Ptr{UInt8}, UInt, Ptr{UInt8}, UInt),
        headers.headers_internal,
        key_bytes,
        UInt(length(key_bytes)),
        value_bytes,
        UInt(length(value_bytes)),
    )
end

function headerfunc(func)
    function func_inner(
        userdata::Any,
        key_ptr::Ptr{UInt8},
        key_len::UInt,
        value_ptr::Ptr{UInt8},
        value_len::UInt,
    )
        key = unsafe_wrap(Array, key_ptr, key_len)
        value = unsafe_wrap(Array, value_ptr, value_len)
        return func(userdata, key, value)
    end

    func_c = @cfunction($func_inner, Int32, (Any, Ptr{UInt8}, UInt, Ptr{UInt8}, UInt),)

    return func_c
end

function showheader(io, key, value)
    println(io, "$(StringView(key)): $(StringView(value))")
    return HYPER_ITER_CONTINUE
end

function Base.show(io::IO, headers::Headers)
    ccall(
        (:hyper_headers_foreach, libhyper),
        Cvoid,
        (Ptr{HeadersInternal}, Ptr{Cvoid}, Any),
        headers.headers_internal,
        headerfunc(showheader),
        io,
    )
end
