struct Clientconn
    clientconn_internal::Ptr{ClientconnInternal}
end

struct ClientconnOptions
    clientconn_options_internal::Ptr{ClientconnOptionsInternal}

    function ClientconnOptions()
        new(
            ccall(
                (:hyper_clientconn_options_new, libhyper),
                Ptr{ClientconnOptionsInternal},
                (),
            ),
        )
    end
end

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
