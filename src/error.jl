struct HyperError
    error_internal::Ptr{ErrorInternal}
end

function free!(err::HyperError)
    ccall((:hyper_error_free, libhyper), Cvoid, (Ptr{ErrorInternal},), err.error_internal)
end

function Base.getproperty(err::HyperError, key::Symbol)
    if key == :code
        return Code(
            ccall(
                (:hyper_error_code, libhyper),
                Int32,
                (Ptr{ErrorInternal},),
                err.error_internal,
            ),
        )
    elseif key == :msg
        buf = zeros(UInt8, 8192)
        msg_len = ccall(
            (:hyper_error_print, libhyper),
            UInt,
            (Ptr{ErrorInternal}, Ptr{UInt8}, UInt),
            err.error_internal,
            buf,
            UInt(length(buf)),
        )
        return String(buf[1:msg_len])
    else
        return getfield(err, key)
    end
end

function Base.show(io::IO, err::HyperError)
    print(io, err.code, ": ", err.msg)
end
