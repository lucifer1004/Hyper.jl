struct Request
    request_internal::Ptr{RequestInternal}

    function Request()
        new(ccall((:hyper_request_new, libhyper), Ptr{RequestInternal}, ()))
    end
end

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

function on_informational!(request::Request, func, data = nothing)
    return Code(
        ccall(
            (:hyper_request_on_informational, libhyper),
            Int32,
            (Ptr{RequestInternal}, Ptr{Cvoid}, Any),
            request.request_internal,
            reqfunc(func),
            data,
        ),
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
            (Ptr{RequestInternal}, Ptr{UInt8}, UInt),
            request.request_internal,
            value_bytes,
            UInt(length(value_bytes)),
        )
    elseif key == :uri
        value_bytes = Vector{UInt8}(value)

        ccall(
            (:hyper_request_set_uri, libhyper),
            Cvoid,
            (Ptr{RequestInternal}, Ptr{UInt8}, UInt),
            request.request_internal,
            value_bytes,
            UInt(length(value_bytes)),
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
            scheme_len = UInt(0)
        else
            scheme_bytes = Vector{UInt8}(scheme)
            scheme_len = UInt(length(scheme_bytes))
        end

        if isnothing(authority)
            authority_bytes = Ptr{UInt8}()
            authority_len = UInt(0)
        else
            authority_bytes = Vector{UInt8}(authority)
            authority_len = UInt(length(authority_bytes))
        end

        if isnothing(path_and_query)
            path_and_query_bytes = Ptr{UInt8}()
            path_and_query_len = UInt(0)
        else
            path_and_query_bytes = Vector{UInt8}(path_and_query)
            path_and_query_len = UInt(length(path_and_query_bytes))
        end

        return Code(
            ccall(
                (:hyper_request_set_uri_parts, libhyper),
                Int32,
                (
                    Ptr{RequestInternal},
                    Ptr{UInt8},
                    UInt,
                    Ptr{UInt8},
                    UInt,
                    Ptr{UInt8},
                    UInt,
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
