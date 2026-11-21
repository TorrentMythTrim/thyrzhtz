-- Numbers of the lobby (milestone 9). They are technical, not balance
return {
	InviteSeconds = 30,       -- an invitation waits this long for an answer
	InvitesPerParty = 6,      -- unanswered invitations one leader may have at a time
	TeleportAttempts = 3,     -- tries of one teleport before the party is told that it failed
	TeleportRetrySeconds = 2,
	LaunchLockSeconds = 45,   -- a party that has set out cannot be changed for this long; then it is unlocked again
}
