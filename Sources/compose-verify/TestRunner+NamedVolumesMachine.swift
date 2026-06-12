import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runNamedVolumeMachineTests() throws {
        let plan = VolumePlanning.Plan(logicalName: "mydata", runtimeName: "demo_mydata")
        runNamedVolumeMachineCommandTests(plan: plan)
        runNamedVolumeMachineLabelTests()
    }

    private mutating func runNamedVolumeMachineCommandTests(plan: VolumePlanning.Plan) {
        let createArgs = VolumeRunner.machineCreateArguments(plan: plan, projectName: "demo")
        expect(createArgs.prefix(2) == ["volume", "create"], "machine volume create command")
        expect(
            createArgs.contains("--label")
                && createArgs.contains("com.docker.compose.project=demo")
                && createArgs.contains("com.docker.compose.volume=mydata"),
            "machine volume create labels"
        )
        expect(createArgs.last == "demo_mydata", "machine volume create runtime name")
        expect(
            VolumeRunner.machineRemoveArguments(plan: plan) == ["volume", "rm", "demo_mydata"],
            "machine volume remove command"
        )
        expect(
            VolumeRunner.machineInspectArguments(name: "demo_mydata") == ["volume", "inspect", "demo_mydata"],
            "machine volume inspect command"
        )
        expect(
            VolumeRunner.machineListArguments() == ["volume", "list", "--quiet"],
            "machine volume list command"
        )
    }

    private mutating func runNamedVolumeMachineLabelTests() {
        let labeled = VolumeConfiguration(
            name: "demo_mydata",
            source: "/var/volumes/demo_mydata",
            labels: ComposeLabels.volumeLabels(projectName: "demo", logicalName: "mydata")
        )
        let unlabeled = VolumeConfiguration(name: "demo_mydata", source: "/var/volumes/demo_mydata")
        let foreign = VolumeConfiguration(
            name: "demo_mydata",
            source: "/var/volumes/demo_mydata",
            labels: ["com.docker.compose.project": "other"]
        )

        expect(VolumeRunner.isProjectVolume(labeled, projectName: "demo"), "machine project volume label match")
        expect(!VolumeRunner.isProjectVolume(unlabeled, projectName: "demo"), "machine unlabeled volume rejected")
        expect(!VolumeRunner.isProjectVolume(foreign, projectName: "demo"), "machine foreign project volume rejected")
        expect(
            !VolumeRunner.shouldRemoveInMachine(configuration: nil, projectName: "demo"),
            "machine remove skips missing inspect"
        )
        expect(
            VolumeRunner.shouldRemoveInMachine(configuration: labeled, projectName: "demo"),
            "machine remove allows labeled project volume"
        )
        expect(
            !VolumeRunner.shouldRemoveInMachine(configuration: unlabeled, projectName: "demo"),
            "machine remove skips unlabeled volume"
        )
    }
}
