struct Buf <: AbstractVector{UInt8}
    buf_internal::Ptr{BufInternal}
end

function Buf(bytes_arr::AbstractVector{UInt8})
    return Buf(
        ccall(
            (:hyper_buf_copy, libhyper),
            Ptr{BufInternal},
            (Ptr{UInt8}, UInt),
            bytes_arr,
            UInt(length(bytes_arr)),
        ),
    )
end

function Buf(buf::Buf)
    return Buf(bytes(buf))
end

function free!(buf::Buf)
    ccall((:hyper_buf_free, libhyper), Cvoid, (Ptr{BufInternal},), buf.buf_internal)
end

function len(buf::Buf)
    return ccall((:hyper_buf_len, libhyper), UInt, (Ptr{BufInternal},), buf.buf_internal)
end

function Base.size(buf::Buf)
    return (Int(len(buf)),)
end

function Base.getindex(buf::Buf, i)
    return Base.getindex(bytes(buf), i)
end

function bytes(buf::Buf)
    bytes_ptr = ccall(
        (:hyper_buf_bytes, libhyper),
        Ptr{UInt8},
        (Ptr{BufInternal},),
        buf.buf_internal,
    )
    return unsafe_wrap(Array, bytes_ptr, len(buf))
end

function Base.show(io::IO, buf::Buf)
    print(io, String(bytes(buf)))
end
