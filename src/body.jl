mutable struct Body
    body_internal::Ptr{BodyInternal}
    consumed::Bool

    function Body(
        body_internal::Ptr{BodyInternal} = ccall(
            (:hyper_body_new, libhyper),
            Ptr{BodyInternal},
            (),
        ),
    )
        new(body_internal, false)
    end
end

function free!(body::Body)
    if !body.consumed
        ccall((:hyper_body_free, libhyper), Cvoid, (Ptr{BodyInternal},), body.body_internal)
    end
end

function poll(body::Body)
    if !body.consumed
        return HyperTask(
            ccall(
                (:hyper_body_data, libhyper),
                Ptr{TaskInternal},
                (Ptr{BodyInternal},),
                body.body_internal,
            ),
        )
    end
end

function body_foreachfunc(func)
    function func_inner(userdata::Any, buf_ptr::Ptr{BufInternal})
        buf = Buf(buf_ptr)
        return func(userdata, buf)
    end

    func_c = @cfunction($func_inner, Int32, (Any, Ptr{BufInternal}))

    return func_c
end

function body_datafunc(func)
    function func_inner(
        userdata::Any,
        ctx_ptr::Ptr{ContextInternal},
        buf_ptr::Ptr{Ptr{BufInternal}},
    )
        ctx = Context(ctx_ptr)
        buf_ref = Ref{Union{Buf,Nothing}}(nothing)
        res = func(userdata, ctx, buf_ref)
        unsafe_store!(
            buf_ptr,
            isnothing(buf_ref[]) ? Ptr{BufInternal}() : buf_ref[].buf_internal,
        )

        return res
    end

    func_c =
        @cfunction($func_inner, Int32, (Any, Ptr{ContextInternal}, Ptr{Ptr{BufInternal}}))

    return func_c
end

function foreach!(body::Body, func, userdata = nothing)
    if !body.consumed
        body.consumed = true
        task_ptr = ccall(
            (:hyper_body_foreach, libhyper),
            Ptr{TaskInternal},
            (Ptr{BodyInternal}, Ptr{Cvoid}, Any),
            body.body_internal,
            body_foreachfunc(func),
            userdata,
        )
        return HyperTask(task_ptr)
    end
end

function Base.setproperty!(body::Body, key::Symbol, value)
    if !body.consumed
        if key == :datafunc
            ccall(
                (:hyper_body_set_data_func, libhyper),
                Cvoid,
                (Ptr{BodyInternal}, Ptr{Cvoid}),
                body.body_internal,
                body_datafunc(value),
            )
        elseif key == :userdata
            ccall(
                (:hyper_body_set_userdata, libhyper),
                Cvoid,
                (Ptr{BodyInternal}, Any),
                body.body_internal,
                value,
            )
        end
    end
end
