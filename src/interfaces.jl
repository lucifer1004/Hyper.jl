export Body,
    Buf,
    Clientconn,
    ClientconnOptions,
    Context,
    HyperError,
    Executor,
    Headers,
    HyperIO,
    Request,
    Response,
    HyperTask,
    Waker,
    handshake!,
    exec,
    poll,
    poll!,
    free!,
    send!,
    wake!,
    foreach!,
    on_informational!

# Structs

mutable struct Body
    body_internal::Ptr{BodyInternal}
    consumed::Bool

    function Body(
        body_internal::Ptr{BodyInternal}=ccall(
            (:hyper_body_new, libhyper),
            Ptr{BodyInternal},
            (),
        ),
    )
        body = new(body_internal, false)
        # finalizer(free!, body)
    end
end

mutable struct Buf <: AbstractVector{UInt8}
    buf_internal::Ptr{BufInternal}

    function Buf(buf_internal::Ptr{BufInternal})
        buf = new(buf_internal)
        # finalizer(free!, buf)
    end
end

mutable struct Clientconn
    clientconn_internal::Ptr{ClientconnInternal}

    function Clientconn(clientconn_internal::Ptr{ClientconnInternal})
        clientconn = new(clientconn_internal)
        # finalizer(free!, clientconn)
    end
end

mutable struct ClientconnOptions
    clientconn_options_internal::Ptr{ClientconnOptionsInternal}

    function ClientconnOptions()
        clientconn_options = new(
            ccall(
                (:hyper_clientconn_options_new, libhyper),
                Ptr{ClientconnOptionsInternal},
                (),
            ),
        )
        # finalizer(free!, clientconn_options)
    end
end

mutable struct Context
    context_internal::Ptr{ContextInternal}
end

mutable struct HyperError
    error_internal::Ptr{ErrorInternal}
end

mutable struct Executor
    executor_internal::Ptr{ExecutorInternal}
    tasks::Set{Ptr{TaskInternal}}

    function Executor()
        executor =
            new(ccall((:hyper_executor_new, libhyper), Ptr{ExecutorInternal}, ()), Set())
        # finalizer(free!, executor)
    end
end

struct Headers
    headers_internal::Ptr{HeadersInternal}
end

mutable struct HyperIO
    io_internal::Ptr{IOInternal}

    function HyperIO()
        io = new(ccall((:hyper_io_new, libhyper), Ptr{IOInternal}, ()))
        # finalizer(free!, io)
    end
end

mutable struct Request
    request_internal::Ptr{RequestInternal}

    function Request()
        request = new(ccall((:hyper_request_new, libhyper), Ptr{RequestInternal}, ()))
        # finalizer(free!, request)
    end
end

mutable struct Response
    response_internal::Ptr{ResponseInternal}
end

mutable struct HyperTask
    task_internal::Ptr{TaskInternal}

    function HyperTask(task_internal::Ptr{TaskInternal})
        task = new(task_internal)
        # finalizer(free!, task)
    end
end

mutable struct Waker
    waker_internal::Ptr{WakerInternal}
    consumed::Bool # `wake!` consumes the waker, so a flag is added to avoid double-freeing.

    function Waker(waker_internal::Ptr{WakerInternal})
        waker = new(waker_internal, false)
        # finalizer(free!, waker)
    end
end

# Body

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
    function func_inner(userdata::Any, ctx_ptr::Ptr{ContextInternal}, buf_ptr::Ptr{Ptr{BufInternal}})
        ctx = Context(ctx_ptr)
        buf_ref = Ref{Union{Buf,Nothing}}(nothing)
        res = func(userdata, ctx, buf_ref)
        unsafe_store!(buf_ptr, isnothing(buf_ref[]) ? Ptr{BufInternal}() : buf_ref[].buf_internal)

        return res
    end

    func_c = @cfunction($func_inner, Int32, (Any, Ptr{ContextInternal}, Ptr{Ptr{BufInternal}}))

    return func_c
end

function foreach!(body::Body, func, userdata=nothing)
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

# Buf

function Buf(bytes_arr::AbstractVector{UInt8})
    return Buf(
        ccall(
            (:hyper_buf_copy, libhyper),
            Ptr{BufInternal},
            (Ptr{UInt8}, UInt64),
            bytes_arr,
            UInt64(length(bytes_arr)),
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
    return ccall((:hyper_buf_len, libhyper), UInt64, (Ptr{BufInternal},), buf.buf_internal)
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

# Clientconn

function free!(clientconn::Clientconn)
    ccall(
        (:hyper_clientconn_free, libhyper),
        Cvoid,
        (Ptr{ClientconnInternal},),
        clientconn.clientconn_internal,
    )
end

function handshake!(io::HyperIO, options::ClientconnOptions)
    task_ptr = ccall(
        (:hyper_clientconn_handshake, libhyper),
        Ptr{TaskInternal},
        (Ptr{IOInternal}, Ptr{ClientconnOptionsInternal}),
        io.io_internal,
        options.clientconn_options_internal,
    )

    return HyperTask(task_ptr)
end

function send!(clientconn::Clientconn, request::Request)
    task_ptr = ccall(
        (:hyper_clientconn_send, libhyper),
        Ptr{TaskInternal},
        (Ptr{ClientconnInternal}, Ptr{RequestInternal}),
        clientconn.clientconn_internal,
        request.request_internal,
    )

    return HyperTask(task_ptr)
end

# ClientconnOptions

function free!(clientconn_options::ClientconnOptions)
    ccall(
        (:hyper_clientconn_options_free, libhyper),
        Cvoid,
        (Ptr{ClientconnOptionsInternal},),
        clientconn_options.clientconn_options_internal,
    )
end

function exec(clientconn_options::ClientconnOptions, executor::Executor)
    ccall(
        (:hyper_clientconn_options_exec, libhyper),
        Cvoid,
        (Ptr{ClientconnOptionsInternal}, Ptr{ExecutorInternal}),
        clientconn_options.clientconn_options_internal,
        executor.executor_internal,
    )
end

function Base.setproperty!(clientconn_options::ClientconnOptions, key::Symbol, value)
    if key == :use_raw_headers
        ccall(
            (:hyper_clientconn_options_headers_raw, libhyper),
            Cvoid,
            (Ptr{ClientconnOptionsInternal}, Int32),
            clientconn_options.clientconn_options_internal,
            Int32(value),
        )
    elseif key == :use_http2
        ccall(
            (:hyper_clientconn_options_http2, libhyper),
            Cvoid,
            (Ptr{ClientconnOptionsInternal}, Int32),
            clientconn_options.clientconn_options_internal,
            Int32(value),
        )
    end
end

# Context

# Error

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
            UInt64,
            (Ptr{ErrorInternal}, Ptr{UInt8}, UInt64),
            err.error_internal,
            buf,
            UInt64(length(buf)),
        )
        return String(buf[1:msg_len])
    else
        return getfield(err, key)
    end
end

function Base.show(io::IO, err::HyperError)
    print(io, err.code, ": ", err.msg)
end

# Executor

function free!(executor::Executor)
    ccall(
        (:hyper_executor_free, libhyper),
        Cvoid,
        (Ptr{ExecutorInternal},),
        executor.executor_internal,
    )
end

function poll!(executor::Executor)
    task_ptr = ccall(
        (:hyper_executor_poll, libhyper),
        Ptr{TaskInternal},
        (Ptr{ExecutorInternal},),
        executor.executor_internal,
    )

    # It happens that the task polled from the executor is not pushed by us.
    # In this case, we just omit this task.
    if task_ptr == C_NULL || task_ptr ∉ executor.tasks
        return nothing
    else
        pop!(executor.tasks, task_ptr)
        return HyperTask(task_ptr)
    end
end

function Base.push!(executor::Executor, task::HyperTask)
    push!(executor.tasks, task.task_internal)

    return Code(
        ccall(
            (:hyper_executor_push, libhyper),
            Int32,
            (Ptr{ExecutorInternal}, Ptr{TaskInternal}),
            executor.executor_internal,
            task.task_internal,
        ),
    )
end

# Headers

function Base.setproperty!(headers::Headers, key::Symbol, value)
    key_bytes = Vector{UInt8}(String(key))
    value_bytes = Vector{UInt8}(value)

    ccall(
        (:hyper_headers_set, libhyper),
        Cvoid,
        (Ptr{HeadersInternal}, Ptr{UInt8}, UInt64, Ptr{UInt8}, UInt64),
        headers.headers_internal,
        key_bytes,
        UInt64(length(key_bytes)),
        value_bytes,
        UInt64(length(value_bytes)),
    )
end

function Base.push!(headers::Headers, kv::Pair)
    key_bytes = Vector{UInt8}(kv.first)
    value_bytes = Vector{UInt8}(kv.second)

    ccall(
        (:hyper_headers_add, libhyper),
        Cvoid,
        (Ptr{HeadersInternal}, Ptr{UInt8}, UInt64, Ptr{UInt8}, UInt64),
        headers.headers_internal,
        key_bytes,
        UInt64(length(key_bytes)),
        value_bytes,
        UInt64(length(value_bytes)),
    )
end

function headerfunc(func)
    function func_inner(
        userdata::Any,
        key_ptr::Ptr{UInt8},
        key_len::UInt64,
        value_ptr::Ptr{UInt8},
        value_len::UInt64,
    )
        key = unsafe_wrap(Array, key_ptr, key_len)
        value = unsafe_wrap(Array, value_ptr, value_len)
        return func(userdata, key, value)
    end

    func_c = @cfunction($func_inner, Int32, (Any, Ptr{UInt8}, UInt64, Ptr{UInt8}, UInt64),)

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

# IO

function free!(io::HyperIO)
    ccall((:hyper_io_free, libhyper), Cvoid, (Ptr{IOInternal},), io.io_internal)
end

function iofunc(func)
    function func_inner(
        userdata::Any,
        ctx_ptr::Ptr{ContextInternal},
        buf_ptr::Ptr{UInt8},
        buf_len::UInt64,
    )
        ctx = Context(ctx_ptr)
        buf = unsafe_wrap(Array, buf_ptr, buf_len)
        return UInt64(func(userdata, ctx, buf, buf_len))
    end

    func_c =
        @cfunction($func_inner, UInt64, (Any, Ptr{ContextInternal}, Ptr{UInt8}, UInt64))

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

# Request

function free!(request::Request)
    ccall(
        (:hyper_request_free, libhyper),
        Cvoid,
        (Ptr{RequestInternal},),
        request.request_internal,
    )
end

function reqfunc(func)
    function func_inner(userdata::Any, resp_ptr::Ptr{ResponseInternal})
        resp = Response(resp_ptr)
        func(userdata, resp)
    end

    func_c = @cfunction($func_inner, Cvoid, (Any, Ptr{ResponseInternal}))

    return func_c
end

function on_informational!(request::Request, func, data=nothing)
    return Code(
        ccall((:hyper_request_on_informational, libhyper),
            Int32,
            (Ptr{RequestInternal}, Ptr{Cvoid}, Any),
            request.request_internal,
            reqfunc(func),
            data)
    )
end

function Base.getproperty(request::Request, name::Symbol)
    if name == :headers
        headers_ptr = ccall(
            (:hyper_request_headers, libhyper),
            Ptr{HeadersInternal},
            (Ptr{RequestInternal},),
            request.request_internal,
        )
        return Headers(headers_ptr)
    else
        return getfield(request, name)
    end
end

function Base.setproperty!(request::Request, key::Symbol, value)
    if key == :method
        value_bytes = Vector{UInt8}(value)

        ccall(
            (:hyper_request_set_method, libhyper),
            Cvoid,
            (Ptr{RequestInternal}, Ptr{UInt8}, UInt64),
            request.request_internal,
            value_bytes,
            UInt64(length(value_bytes)),
        )
    elseif key == :uri
        value_bytes = Vector{UInt8}(value)

        ccall(
            (:hyper_request_set_uri, libhyper),
            Cvoid,
            (Ptr{RequestInternal}, Ptr{UInt8}, UInt64),
            request.request_internal,
            value_bytes,
            UInt64(length(value_bytes)),
        )
    elseif key == :body && isa(value, Body)
        value.consumed = true

        return Code(
            ccall(
                (:hyper_request_set_body, libhyper),
                Int32,
                (Ptr{RequestInternal}, Ptr{BodyInternal}),
                request.request_internal,
                value.body_internal,
            ),
        )
    elseif key == :version
        return Code(
            ccall(
                (:hyper_request_set_version, libhyper),
                Int32,
                (Ptr{RequestInternal}, Int32),
                request.request_internal,
                Int32(value),
            ),
        )
    elseif key == :uri_parts
        scheme, authority, path_and_query = value
        if isnothing(scheme)
            scheme_bytes = Ptr{UInt8}()
            scheme_len = UInt64(0)
        else
            scheme_bytes = Vector{UInt8}(scheme)
            scheme_len = UInt64(length(scheme_bytes))
        end

        if isnothing(authority)
            authority_bytes = Ptr{UInt8}()
            authority_len = UInt64(0)
        else
            authority_bytes = Vector{UInt8}(authority)
            authority_len = UInt64(length(authority_bytes))
        end

        if isnothing(path_and_query)
            path_and_query_bytes = Ptr{UInt8}()
            path_and_query_len = UInt64(0)
        else
            path_and_query_bytes = Vector{UInt8}(path_and_query)
            path_and_query_len = UInt64(length(path_and_query_bytes))
        end

        return Code(
            ccall(
                (:hyper_request_set_uri_parts, libhyper),
                Int32,
                (
                    Ptr{RequestInternal},
                    Ptr{UInt8},
                    UInt64,
                    Ptr{UInt8},
                    UInt64,
                    Ptr{UInt8},
                    UInt64,
                ),
                request.request_internal,
                scheme_bytes,
                scheme_len,
                authority_bytes,
                authority_len,
                path_and_query_bytes,
                path_and_query_len,
            ),
        )
    end
end

# Response

function free!(response::Response)
    ccall(
        (:hyper_response_free, libhyper),
        Cvoid,
        (Ptr{ResponseInternal},),
        response.response_internal,
    )
end

function Base.getproperty(response::Response, key::Symbol)
    if key == :status
        return ccall(
            (:hyper_response_status, libhyper),
            UInt16,
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
    elseif key == :body
        body_ptr = ccall(
            (:hyper_response_body, libhyper),
            Ptr{BodyInternal},
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
        return Body(body_ptr)
    elseif key == :version
        return ccall(
            (:hyper_response_version, libhyper),
            Int32,
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
    elseif key == :headers
        headers_ptr = ccall(
            (:hyper_response_headers, libhyper),
            Ptr{HeadersInternal},
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
        return Headers(headers_ptr)
    elseif key == :raw_headers
        headers_ptr = ccall(
            (:hyper_response_headers_raw, libhyper),
            Ptr{HeadersInternal},
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
        return Headers(headers_ptr)
    elseif key == :reason
        bytes_len = ccall(
            (:hyper_response_reason_phrase_len, libhyper),
            UInt64,
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
        bytes_ptr = ccall(
            (:hyper_response_reason_phrase, libhyper),
            Ptr{UInt8},
            (Ptr{ResponseInternal},),
            response.response_internal,
        )
        return StringView(unsafe_wrap(Array, bytes_ptr, bytes_len))
    else
        return getfield(response, key)
    end
end

# Task

function free!(task::HyperTask)
    ccall((:hyper_task_free, libhyper), Cvoid, (Ptr{TaskInternal},), task.task_internal)
end

function Base.getproperty(task::HyperTask, key::Symbol)
    if key == :type
        return TaskReturnType(
            ccall(
                (:hyper_task_type, libhyper),
                UInt64,
                (Ptr{TaskInternal},),
                task.task_internal,
            ),
        )
    elseif key == :value
        typ = task.type
        if typ == TASK_EMPTY
            return nothing
        end

        ptr = ccall(
            (:hyper_task_value, libhyper),
            Ptr{Cvoid},
            (Ptr{TaskInternal},),
            task.task_internal,
        )

        if typ == TASK_BUF
            return Buf(Ptr{BufInternal}(ptr))
        elseif typ == TASK_ERROR
            return HyperError(Ptr{ErrorInternal}(ptr))
        elseif typ == TASK_RESPONSE
            return Response(Ptr{ResponseInternal}(ptr))
        else
            return Clientconn(Ptr{ClientconnInternal}(ptr))
        end
    elseif key == :userdata
        return ccall(
            (:hyper_task_userdata, libhyper),
            Any,
            (Ptr{TaskInternal},),
            task.task_internal,
        )
    else
        return getfield(task, key)
    end
end

function Base.setproperty!(task::HyperTask, key::Symbol, value)
    if key == :userdata
        ccall(
            (:hyper_task_set_userdata, libhyper),
            Cvoid,
            (Ptr{TaskInternal}, Any),
            task.task_internal,
            value,
        )
    else
        return setfield!(task, key, value)
    end
end

# Waker

function Waker(ctx::Context)
    waker_ptr = ccall(
        (:hyper_context_waker, libhyper),
        Ptr{WakerInternal},
        (Ptr{ContextInternal},),
        ctx.context_internal,
    )

    return Waker(waker_ptr)
end

"""
$(SIGNATURES)

Free a waker that hasn’t been woken.
"""
function free!(waker::Waker)
    if !waker.consumed
        ccall(
            (:hyper_waker_free, libhyper),
            Cvoid,
            (Ptr{WakerInternal},),
            waker.waker_internal,
        )
    end
end

"""
$(SIGNATURES)

Wake up the task associated with the waker.
"""
function wake!(waker::Waker)
    if !waker.consumed
        waker.consumed = true
        ccall(
            (:hyper_waker_wake, libhyper),
            Cvoid,
            (Ptr{WakerInternal},),
            waker.waker_internal,
        )
    end
end
