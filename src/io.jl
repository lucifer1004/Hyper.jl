struct HyperIO
    io_internal::Ptr{IOInternal}

    function HyperIO()
        new(ccall((:hyper_io_new, libhyper), Ptr{IOInternal}, ()))
    end
end

function free!(io::HyperIO)
    ccall((:hyper_io_free, libhyper), Cvoid, (Ptr{IOInternal},), io.io_internal)
end

function iofunc(func)
    function func_inner(
        userdata::Any,
        ctx_ptr::Ptr{ContextInternal},
        buf_ptr::Ptr{UInt8},
        buf_len::UInt,
    )
        ctx = Context(ctx_ptr)
        buf = unsafe_wrap(Array, buf_ptr, buf_len)
        return UInt(func(userdata, ctx, buf, buf_len))
    end

    func_c = @cfunction($func_inner, UInt, (Any, Ptr{ContextInternal}, Ptr{UInt8}, UInt))

    return func_c
end

function Base.setproperty!(io::HyperIO, key::Symbol, value)
    if key ∈ [:read, :write]
        if !isa(value, Union{Base.CFunction,Ptr{Cvoid}})
            value = iofunc(value)
        end

        if key == :read
            ccall(
                (:hyper_io_set_read, libhyper),
                Cvoid,
                (Ptr{IOInternal}, Ptr{Cvoid}),
                io.io_internal,
                value,
            )
        else
            ccall(
                (:hyper_io_set_write, libhyper),
                Cvoid,
                (Ptr{IOInternal}, Ptr{Cvoid}),
                io.io_internal,
                value,
            )
        end
    elseif key == :userdata
        ccall(
            (:hyper_io_set_userdata, libhyper),
            Cvoid,
            (Ptr{IOInternal}, Any),
            io.io_internal,
            value,
        )
    end
end
