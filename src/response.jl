struct Response
    response_internal::Ptr{ResponseInternal}
end

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
            UInt,
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
