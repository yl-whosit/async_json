local NAMESPACE = "async_json:"
local key = {}
key.JOB_COUNTER = NAMESPACE .. "job_count"
key.THE_WORKER = NAMESPACE .. "worker_running"
key.TASK_COUNT = NAMESPACE .. "task_count"
key.FIFO_PREFIX = NAMESPACE .. "fifo_task"
key.FIFO_FRONT = NAMESPACE .. "fifo_front"
key.FIFO_BACK = NAMESPACE .. "fifo_back"

return key
