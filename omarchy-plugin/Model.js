.pragma library

var RUNNING_STATE = "running"
var ACTIONS = ["start", "stop"]

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
    if (!json || typeof json !== "object" || !json.ID)
        return undefined
    return {
        id: json.ID,
        name: json.Names || "",
        image: json.Image || "",
        state: json.State || "",
        status: json.Status || "",
        ports: json.Ports || ""
    }
}

function isRunning(container) {
    return container.state === RUNNING_STATE
}

function toggleAction(container) {
    return isRunning(container) ? "stop" : "start"
}

function runningCount(containers) {
    return containers.filter(isRunning).length
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

var CONTAINER_FIELDS = ["id", "name", "image", "state", "status", "ports"]

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
