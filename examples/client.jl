using Hyper
using Sockets
using StringViews

include("utils.jl")

function print_each_chunk(userdata, buf::Buf)
    print(StringView(buf))
    return HYPER_ITER_CONTINUE
end

function main()
    host = length(ARGS) > 0 ? ARGS[1] : "httpbin.org"
    port = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 80
    path = length(ARGS) > 2 ? ARGS[3] : "/"

    println("connecting to port $port on $host...")
    socket = connect(host, port)
    conn = ConnData(socket, nothing, nothing, nothing)
    io = HyperIO()
    io.userdata = conn
    io.read = read_cb!
    io.write = write_cb!

    println("http handshake (hyper v$(Hyper.version())) ...")

    executor = Executor()
    opts = ClientconnOptions()
    exec(opts, executor)

    hs = handshake!(io, opts)
    hs.userdata = EXAMPLE_HANDSHAKE
    push!(executor, hs)

    while true
        while true
            task = poll!(executor)

            if isnothing(task)
                break
            end

            task_type = task.userdata
            if task_type == EXAMPLE_HANDSHAKE
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_CLIENTCONN

                println("preparing http request ...")
                client = task.value
                Hyper.free!(task)

                req = Request()
                req.method = "GET"
                req.uri = path

                headers = req.headers
                headers.Host = host

                send_task = send!(client, req)
                send_task.userdata = EXAMPLE_SEND

                println("sending ...")
                push!(executor, send_task)
                Hyper.free!(client)

                break
            elseif task_type == EXAMPLE_SEND
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_RESPONSE

                resp = task.value
                Hyper.free!(task)

                http_status = resp.status
                reason = resp.reason

                println("Response Status: $http_status $reason")
                headers = resp.headers
                println(headers)

                body = resp.body
                foreach_task = foreach!(body, print_each_chunk)
                foreach_task.userdata = EXAMPLE_RESP_BODY
                push!(executor, foreach_task)
                Hyper.free!(resp)

                break
            elseif task_type == EXAMPLE_RESP_BODY
                if task.type == Hyper.TASK_ERROR
                    @error task.value
                    return
                end

                @assert task.type == Hyper.TASK_EMPTY
                println(" -- Done! -- ")

                Hyper.free!(task)
                Hyper.free!(executor)
                free!(conn)

                return 0
            elseif task_type == EXAMPLE_NOT_SET
                Hyper.free!(task)
                break
            else
                @error "Unknown task type"
                return
            end
        end

        if !isnothing(conn.task)
            wait(conn.task)
        end

        if !isnothing(conn.read_waker)
            wake!(conn.read_waker)
            conn.read_waker = nothing
        end

        if !isnothing(conn.write_waker)
            wake!(conn.write_waker)
            conn.write_waker = nothing
        end
    end
end

main()
