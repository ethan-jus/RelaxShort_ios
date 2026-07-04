import Testing
@testable import RelaxShort

struct ProfileIdentityTests {
    @Test
    func derivesStableUppercaseGuestID() {
        let id = ProfileGuestIdentity.shortID(
            from: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        )

        #expect(id == "A1B2C3D4")
    }
}
