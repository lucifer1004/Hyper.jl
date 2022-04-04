"""
An async context for a task that contains the related waker.
"""
struct Context
    context_internal::Ptr{ContextInternal}
end

"""
An async task.
"""
struct HyperTask
    task_internal::Ptr{TaskInternal}
end

function free!(task::HyperTask)
    ccall((:hyper_task_free, libhyper), Cvoid, (Ptr{TaskInternal},), task.task_internal)
end

function Base.getproperty(task::HyperTask, key::Symbol)
    if key == :type
        return TaskReturnType(
            ccall(
                (:hyper_task_type, libhyper),
                UInt,
                (Ptr{TaskInternal},),
                task.task_internal,
            ),
        )
    elseif key == :value
        typ = task.type
        if typ == HYPER_TASK_EMPTY
            return nothing
        end

        ptr = ccall(
            (:hyper_task_value, libhyper),
            Ptr{Cvoid},
            (Ptr{TaskInternal},),
            task.task_internal,
        )

        if typ == HYPER_TASK_BUF
            return Buf(Ptr{BufInternal}(ptr))
        elseif typ == HYPER_TASK_ERROR
            return HyperError(Ptr{ErrorInternal}(ptr))
        elseif typ == HYPER_TASK_RESPONSE
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

"""
A waker that is saved and used to waken a pending task.
"""
mutable struct Waker
    waker_internal::Ptr{WakerInternal}
    consumed::Bool # `wake!` consumes the waker, so a flag is added to avoid double-freeing.

    function Waker(waker_internal::Ptr{WakerInternal})
        new(waker_internal, false)
    end
end

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

"""
A task executor for `HyperTask`s.
"""
struct Executor
    executor_internal::Ptr{ExecutorInternal}
    tasks::Set{Ptr{TaskInternal}}

    function Executor()
        new(ccall((:hyper_executor_new, libhyper), Ptr{ExecutorInternal}, ()), Set())
    end
end

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
