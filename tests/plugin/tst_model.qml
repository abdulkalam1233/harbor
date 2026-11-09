import QtTest
import "../../omarchy-plugin/Model.js" as Model

TestCase {
    name: "BarWidgetModel"

    readonly property string twoContainers:
        '{"ID":"aaa111","Names":"web","Image":"nginx","State":"running","Status":"Up 2 minutes","Ports":"0.0.0.0:80->80/tcp"}\n'
        + '{"ID":"bbb222","Names":"db","Image":"postgres","State":"exited","Status":"Exited (0) 1 hour ago","Ports":""}\n'

    function test_parsesTheTwoContainerListingIntoFields() {
        const containers = Model.parseContainers(twoContainers)
        compare(containers.length, 2)
        compare(containers[0].id, "aaa111")
        compare(containers[0].name, "web")
        compare(containers[0].image, "nginx")
        compare(containers[0].state, "running")
        compare(containers[0].status, "Up 2 minutes")
        compare(containers[0].ports, "0.0.0.0:80->80/tcp")
        compare(containers[1].id, "bbb222")
        compare(containers[1].name, "db")
        compare(containers[1].state, "exited")
    }

    function test_skipsMalformedAndIdlessLines() {
        const text = 'not json\n\n{"Names":"orphan","State":"running"}\n[1,2]\n'
            + '{"ID":"ccc333","Names":"cache","State":"running"}\n'
        const containers = Model.parseContainers(text)
        compare(containers.length, 1)
        compare(containers[0].id, "ccc333")
    }

    function test_countsOnlyRunningContainers() {
        const containers = [
            { state: "running" }, { state: "exited" }, { state: "paused" },
            { state: "restarting" }, { state: "running" }
        ]
        compare(Model.runningCount(containers), 2)
        verify(!Model.isRunning({ state: "restarting" }))
        verify(!Model.isRunning({ state: "paused" }))
        verify(Model.isRunning({ state: "running" }))
    }

    function test_countsTheTwoContainerListingAsOneRunning() {
        compare(Model.runningCount(Model.parseContainers(twoContainers)), 1)
    }

    function test_reportsMissingDockerWhenItFailedToStart() {
        compare(Model.failureKind("", true), "missing")
    }

    function test_classifiesPermissionDenied() {
        compare(Model.failureKind("  Got PERMISSION DENIED while trying to connect to the socket\n", false), "denied")
    }

    function test_classifiesStoppedDaemon() {
        compare(Model.failureKind("Cannot connect to the Docker daemon at unix:///var/run/docker.sock", false), "stopped")
    }

    function test_classifiesOtherOutputAsUnknown() {
        compare(Model.failureKind("something else broke", false), "unknown")
        compare(Model.failureKind("", false), "unknown")
    }

    function test_listsContainersWithOneArgumentPerToken() {
        compare(Model.listCommand(), ["docker", "ps", "--all", "--no-trunc", "--format", "{{json .}}"])
    }

    function test_buildsStartAndStopCommandsWithTheIdAsItsOwnArgument() {
        compare(Model.actionCommand("start", "aaa111; rm -rf /"), ["docker", "start", "aaa111; rm -rf /"])
        compare(Model.actionCommand("stop", "bbb222"), ["docker", "stop", "bbb222"])
    }

    function test_rejectsUnknownActionsAndEmptyIds() {
        compare(Model.actionCommand("remove", "aaa111"), null)
        compare(Model.actionCommand("restart", "aaa111"), null)
        compare(Model.actionCommand("start", ""), null)
    }

    function test_treatsAnEqualReparseAsUnchanged() {
        verify(Model.sameContainers(Model.parseContainers(twoContainers), Model.parseContainers(twoContainers)))
    }

    function test_treatsAStateFlipAsChanged() {
        const before = Model.parseContainers(twoContainers)
        const after = Model.parseContainers(twoContainers.replace('"exited"', '"running"'))
        verify(!Model.sameContainers(before, after))
        verify(!Model.sameContainers(before, before.slice(0, 1)))
    }

    function test_offersStopForRunningContainersAndStartForTheRest() {
        compare(Model.toggleAction({ state: "running" }), "stop")
        compare(Model.toggleAction({ state: "exited" }), "start")
        compare(Model.toggleAction({ state: "paused" }), "start")
    }
}
