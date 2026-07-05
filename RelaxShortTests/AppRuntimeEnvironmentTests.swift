import Testing
@testable import RelaxShort

@Suite
struct AppRuntimeEnvironmentTests {
    @Test
    func detectsXCTestHostFromConfigurationPath() {
        #expect(AppRuntimeEnvironment.isUnitTesting(
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]
        ))
    }

    @Test
    func normalAppEnvironmentIsNotUnitTesting() {
        #expect(!AppRuntimeEnvironment.isUnitTesting(environment: [:]))
    }
}
