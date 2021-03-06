/*
 * Copyright (c) 2003, Intel Corporation. All rights reserved.
 * Created by:  crystal.xiong REMOVE-THIS AT intel DOT com
 * This file is licensed under the GPL license.  For the full content
 * of this license, see the COPYING file at the top level of this
 * source tree.
 */

/*
 * mq_timedreceive() test plan:
 * mq_timedreceive() will fail with EBADF, if mqdes is not a valid message
 * message queue descriptor.
 */

#include <stdio.h>
#include <errno.h>
#include <mqueue.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "posixtest.h"

#define TEST "14-1"
#define FUNCTION "mq_timedreceive"
#define ERROR_PREFIX "unexpected error: " FUNCTION " " TEST ": "

#define NAMESIZE	50
#define BUFFER		40

int main()
{
	char mqname[NAMESIZE];
	mqd_t mqdes;
	char msgrv[BUFFER];
	struct timespec ts;
	struct mq_attr attr;
	int unresolved = 0, failure = 0;

	sprintf(mqname, "/" FUNCTION "_" TEST "_%d", getpid());

	attr.mq_msgsize = BUFFER;
	attr.mq_maxmsg = BUFFER;
	mqdes = mq_open(mqname, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR, &attr);
	if (mqdes == (mqd_t)-1) {
		perror(ERROR_PREFIX "mq_open()");
		unresolved = 1;
	}
	mqdes = mqdes + 1;
	ts.tv_sec = time(NULL) + 1;
	ts.tv_nsec = 0;
	if (mq_timedreceive(mqdes, msgrv, BUFFER, NULL, &ts) == -1) {
		if (EBADF != errno) {
			printf("errno != EBADF\n");
			failure = 1;
		}
	} else {
		printf("mq_timedreceive() succeed unexpectly\n");
		failure = 1;
	}
	if (mq_close(mqdes - 1) != 0) {
		perror(ERROR_PREFIX "mq_close()");
		unresolved = 1;
	}
	if (mq_unlink(mqname) != 0) {
		perror(ERROR_PREFIX "mq_unlink()");
		unresolved = 1;
	}
	if (failure == 1) {
		printf("Test FAILED\n");
		return PTS_FAIL;
	}
	if (unresolved == 1) {
		printf("Test UNRESOLVED\n");
		return PTS_UNRESOLVED;
	}
	printf("Test PASSED\n");
	return PTS_PASS;
}
