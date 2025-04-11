local NAMESPACE = "json_storage:"
key = {}
key.JOB_COUNTER = NAMESPACE .. "job_count" -- TODO REMOVE
key.MORE_TASKS = NAMESPACE .. "more_tasks"
key.THE_WORKER = NAMESPACE .. "worker_running"
key.FIFO_PREFIX = NAMESPACE .. "fifo_task"
key.FIFO_FRONT = NAMESPACE .. "fifo_front"
key.FIFO_BACK = NAMESPACE .. "fifo_back"
key.TASK_COUNT = NAMESPACE .. "task_count"

return key