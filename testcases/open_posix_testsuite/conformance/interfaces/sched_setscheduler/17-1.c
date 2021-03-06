/*
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *
 * Test that the policy and scheduling parameters remain unchanged when the
 * sched_priority member is not within the inclusive priority range for the
 * scheduling policy.
 *
 * Test is done for all policy defined in the spec into a loop.
 * Steps (into loop):
 *   1. Get the old policy and priority.
 *   2. Call sched_setscheduler with invalid args.
 *   3. Check that the policy and priority have not changed.
 */

#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <unistd.h>
#include "posixtest.h"

struct unique {
	int value;
	char *name;
} sym[] = {

	{
		SCHED_FIFO, "SCHED_FIFO"
	},
	{
		SCHED_RR, "SCHED_RR"
	},
#if defined(_POSIX_SPORADIC_SERVER)&&(_POSIX_SPORADIC_SERVER != -1) || defined(_POSIX_THREAD_SPORADIC_SERVER)&&(_POSIX_THREAD_SPORADIC_SERVER != -1)
	{
		SCHED_SPORADIC,"SCHED_SPORADIC"
	},
#endif
	{
		SCHED_OTHER, "SCHED_OTHER"
	},
	{
		0, 0
	}
};

int main() {
	int policy, invalid_priority, result = PTS_PASS;
	int old_priority, old_policy, new_policy;
	struct sched_param param;

	struct unique *tst;

	tst = sym;
	while (tst->name) {
		policy = tst->value;
		fflush(stderr);
		printf("Policy: %s\n", tst->name);
		fflush(stdout);

		if (sched_getparam(getpid(), &param) != 0) {
			perror("An error occurs when calling sched_getparam()");
			return PTS_UNRESOLVED;
		}
		old_priority = param.sched_priority;

		old_policy = sched_getscheduler(getpid());
		if (old_policy == -1) {
			perror("An error occurs when calling sched_getscheduler()");
			return PTS_UNRESOLVED;
		}

		invalid_priority = sched_get_priority_max(policy);
		if (invalid_priority == -1) {
			perror("An error occurs when calling sched_get_priority_max()");
			return PTS_UNRESOLVED;
		}

		/* set an invalid priority */
		invalid_priority++;
		param.sched_priority = invalid_priority;

		sched_setscheduler(0, policy, &param);

		if (sched_getparam(getpid(), &param) != 0) {
			perror("An error occurs when calling sched_getparam()");
			return PTS_UNRESOLVED;
		}

		new_policy = sched_getscheduler(getpid());
		if (new_policy == -1) {
			perror("An error occurs when calling sched_getscheduler()");
			return PTS_UNRESOLVED;
		}

		if (old_policy == new_policy &&
		   old_priority == param.sched_priority) {
			printf("  OK\n");
		} else {
			if (param.sched_priority != old_priority) {
				printf("  The param has changed\n");
			}
			if (new_policy != old_policy) {
				printf("  The policy has changed\n");
			}
			result = PTS_FAIL;
		}

		tst++;
	}

	if (result == PTS_PASS) {
		printf("Test PASSED\n");
	}
	return result;
}