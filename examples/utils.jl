mutable struct ConnData
    io::IO
    task::Union{Task, Nothing}
    read_waker::Union{Waker,Nothing}
    write_waker::Union{Waker,Nothing}
end

@enum ExampleType EXAMPLE_NOT_SET EXAMPLE_HANDSHAKE EXAMPLE_SEND EXAMPLE_RESP_BODY

function read_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::UInt64)
    try
        avail = bytesavailable(conn.io)
        if avail > 0
            conn.task = nothing
            return readbytes!(conn.io, buf, min(buf_len, avail))
        else
            conn.task = @async begin
                Base.start_reading(conn.io)
            end

            if !isnothing(conn.read_waker)
                Hyper.free!(conn.read_waker)
            end
        
            conn.read_waker = Waker(ctx)
            return HYPER_IO_PENDING
        end
    catch e
        @error e
        return HYPER_IO_ERROR
    end
end

function write_cb!(conn, ctx::Context, buf::AbstractVector{UInt8}, buf_len::Integer)
    try
        ret = write(conn.io, buf[1:min(length(buf), buf_len)])
        return ret
    catch e
        @error e
        return HYPER_IO_ERROR
    end
end

function free!(conn::ConnData)
    if !isnothing(conn.read_waker)
        Hyper.free!(conn.read_waker)
    end
    conn.read_waker = nothing

    if !isnothing(conn.write_waker)
        Hyper.free!(conn.write_waker)
    end
    conn.write_waker = nothing

    close(conn.io)
end
