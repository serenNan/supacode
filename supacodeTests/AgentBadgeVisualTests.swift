import Testing

@testable import supacode

struct AgentBadgeVisualTests {
  @Test func resolvesEachActivityToItsVariant() {
    #expect(AgentBadgeVisual.resolve(.idle) == .normal)
    #expect(AgentBadgeVisual.resolve(.busy) == .normal)
    #expect(AgentBadgeVisual.resolve(.awaitingInput) == .awaitingInput)
    #expect(AgentBadgeVisual.resolve(.compacting) == .compacting)
    #expect(AgentBadgeVisual.resolve(.errored) == .errored)
  }
}

struct SidebarAgentFallbackTests {
  @Test func errorFallbackOnlyWhenNoVisibleAgents() {
    // Badges off (no avatar to carry the state) → the standalone warning shows.
    #expect(SidebarAgentFallback.showsError(hasAgentError: true, hasVisibleAgents: false))
    // Badge present → the avatar itself turns red, so no separate glyph.
    #expect(!SidebarAgentFallback.showsError(hasAgentError: true, hasVisibleAgents: true))
    #expect(!SidebarAgentFallback.showsError(hasAgentError: false, hasVisibleAgents: false))
  }

  @Test func compactingFallbackYieldsToErrorAndNeedsNoVisibleAgents() {
    #expect(SidebarAgentFallback.showsCompacting(isCompacting: true, hasAgentError: false, hasVisibleAgents: false))
    // A broken turn isn't compacting: error supersedes.
    #expect(!SidebarAgentFallback.showsCompacting(isCompacting: true, hasAgentError: true, hasVisibleAgents: false))
    // Badge carries the compacting ring when the avatar is visible.
    #expect(!SidebarAgentFallback.showsCompacting(isCompacting: true, hasAgentError: false, hasVisibleAgents: true))
  }
}
