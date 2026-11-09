.pragma library

var RUNNING_STATE = "running"
var ACTION = { start: "start", stop: "stop" }
var ACTIONS = [ACTION.start, ACTION.stop]

var FIELD_SOURCES = { id: "ID", name: "Names", image: "Image", state: "State", status: "Status", ports: "Ports" }
var CONTAINER_FIELDS = Object.keys(FIELD_SOURCES)

var FAILURE_SYMPTOMS = [
    { symptom: "permission denied while trying to connect", kind: "denied" },
    { symptom: "cannot connect to the docker daemon", kind: "stopped" }
]

function listCommand() {
    return ["docker", "ps", "--all", "--no-trunc", "--format", "{{json .}}"]
}

function actionCommand(action, id) {
    if (ACTIONS.indexOf(action) < 0 || !id)
        return null
    return ["docker", action, id]
}

function parseContainers(text) {
    return text.split("\n").map(parseLine).filter(function (container) {
        return container !== undefined
    })
}

function parseLine(line) {
    var json
    try {
        json = JSON.parse(line)
    } catch (error) {
        return undefined
    }
    if (!json || typeof json !== "object" || !json[FIELD_SOURCES.id])
        return undefined
    var container = {}
    CONTAINER_FIELDS.forEach(function (field) {
        container[field] = json[FIELD_SOURCES[field]] || ""
    })
    return container
}

function isRunning(container) {
    return container.state === RUNNING_STATE
}

function toggleAction(container) {
    return isRunning(container) ? ACTION.stop : ACTION.start
}

function isBusy(busyIds, id) {
    return busyIds.indexOf(id) >= 0
}

function withBusy(busyIds, id) {
    return isBusy(busyIds, id) ? busyIds : busyIds.concat([id])
}

function withoutBusy(busyIds, id) {
    return busyIds.filter(function (busyId) {
        return busyId !== id
    })
}

var IDLE_REFRESH = { running: false, again: false }

function requestRefresh(queue) {
    if (queue.running)
        return { queue: { running: true, again: true }, start: false }
    return { queue: { running: true, again: false }, start: true }
}

function finishRefresh(queue) {
    if (queue.again)
        return { queue: { running: true, again: false }, start: true }
    return { queue: IDLE_REFRESH, start: false }
}

function runningCount(containers) {
    return containers.filter(isRunning).length
}

function clampCursor(index, stopCount) {
    return Math.max(0, Math.min(stopCount - 1, index))
}

function failureKind(output, failedToStart) {
    if (failedToStart)
        return "missing"
    var text = output.trim().toLowerCase()
    for (var i = 0; i < FAILURE_SYMPTOMS.length; i++)
        if (text.indexOf(FAILURE_SYMPTOMS[i].symptom) >= 0)
            return FAILURE_SYMPTOMS[i].kind
    return "unknown"
}

function sameContainer(a, b) {
    return CONTAINER_FIELDS.every(function (field) {
        return a[field] === b[field]
    })
}

function sameContainers(a, b) {
    return a.length === b.length && a.every(function (container, index) {
        return sameContainer(container, b[index])
    })
}
