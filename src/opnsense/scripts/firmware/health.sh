#!/bin/sh

# Copyright (C) 2017-2024 Franco Fichtner <franco@opnsense.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

REQUEST="AUDIT HEALTH"

. /usr/local/opnsense/scripts/firmware/config.sh

TMPFILE=/tmp/pkg_check.exclude
MTREE="mtree -e -p /"
CMD=${1}

MTREE_PATTERNS="
./.cshrc
./.profile
./etc/csh.cshrc
./etc/group
./etc/hosts
./etc/master.passwd
./etc/newsyslog.conf
./etc/pam.d/sshd
./etc/pam.d/system
./etc/passwd
./etc/pwd.db
./etc/rc
./etc/rc.shutdown
./etc/remote
./etc/shells
./etc/spwd.db
./etc/ssl/openssl.cnf
./etc/ttys
./root/.cshrc
./root/.profile
./usr/share/man/mandoc.db
./usr/share/openssl/man/mandoc.db
"

GREP_PATTERNS=

for PATTERN in ${MTREE_PATTERNS}; do
	GREP_PATTERNS="$(echo "${GREP_PATTERNS}${PATTERN} missing")
"
done

VERSION=$(opnsense-update -v)

set_check()
{
	SET=${1}

	VER=$(opnsense-version -v ${SET})

	echo ">>> Check installed ${SET} version" | ${TEE} ${LOCKFILE}

	if [ -z "${VER}" -o -z "${VERSION}" ]; then
		echo "Failed to determine version info." | ${TEE} ${LOCKFILE}
	elif [ "${VER}" != "${VERSION}" ]; then
		echo "Version ${VER} is incorrect, expected: ${VERSION}" | ${TEE} ${LOCKFILE}
	else
		echo "Version ${VER} is correct." | ${TEE} ${LOCKFILE}
	fi

	FILE=/usr/local/opnsense/version/${SET}.mtree

	if [ ! -f ${FILE} ]; then
		echo "Cannot verify ${SET}: missing ${FILE}" | ${TEE} ${LOCKFILE}
		return
	fi

	if [ ! -f ${FILE}.sig ]; then
		echo "Unverified consistency check for ${SET}: missing ${FILE}.sig" | ${TEE} ${LOCKFILE}
	elif ! opnsense-verify -q ${FILE}; then
		echo "Unverified consistency check for ${SET}: invalid ${FILE}.sig" | ${TEE} ${LOCKFILE}
	fi

	echo ">>> Check for missing or altered ${SET} files" | ${TEE} ${LOCKFILE}

	echo "${MTREE_PATTERNS}" > ${TMPFILE}

	MTREE_OUT=$(${MTREE} -X ${TMPFILE} < ${FILE} 2>&1)
	MTREE_RET=${?}

	MTREE_OUT=$(echo "${MTREE_OUT}" | grep -Fvx "${GREP_PATTERNS}")
	MTREE_MIA=$(echo "${MTREE_OUT}" | grep -c ' missing$')

	if [ ${MTREE_RET} -eq 0 ]; then
		if [ "${MTREE_MIA}" = "0" ]; then
			echo "No problems detected." | ${TEE} ${LOCKFILE}
		else
			echo "Missing files: ${MTREE_MIA}" | ${TEE} ${LOCKFILE}
			echo "${MTREE_OUT}" | ${TEE} ${LOCKFILE}
		fi
	else
		echo "Error ${MTREE_RET} occurred." | ${TEE} ${LOCKFILE}
		echo "${MTREE_OUT}" | ${TEE} ${LOCKFILE}
	fi

	rm ${TMPFILE}
}

core_check()
{
	echo ">>> Check for core packages consistency" | ${TEE} ${LOCKFILE}

	CORE=$(opnsense-version -n)
	PROGRESS=

	if [ -z "${CORE}" ]; then
		echo "Could not determine core package name."
		return
	fi

	if [ -z "$(${PKG} query %n ${CORE})" ]; then
		echo "Core package \"${CORE}\" not known to package database." | ${TEE} ${LOCKFILE}
		return
	fi

	echo "Core package \"${CORE}\" at $(opnsense-version -v) has $(${PKG} query %#d ${CORE}) dependencies to check." | ${TEE} ${LOCKFILE}

	for DEP in $( (echo ${CORE}; ${PKG} query %dn ${CORE}) | sort -u); do
		if [ -z "${PROGRESS}" ]; then
			echo -n "Checking packages: ." | ${TEE} ${LOCKFILE}
			PROGRESS=1
		else
			echo -n "." | ${TEE} ${LOCKFILE}
		fi

		read REPO LVER AUTO VITA << EOF
$(${PKG} query "%R %v %a %V" ${DEP})
EOF

		if [ -z "${REPO}${LVER}${AUTO}${VITA}" ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "Package not installed: ${DEP}" | ${TEE} ${LOCKFILE}
			PROGRESS=
			continue
		fi

		if [ "${REPO}" != ${PRODUCT} ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "${DEP}-${LVER} repository mismatch: ${REPO}" | ${TEE} ${LOCKFILE}
			PROGRESS=
		fi

		RVER=$(${PKG} rquery -r ${PRODUCT} %v ${DEP} 2> /dev/null)
		if [ -z "${RVER}" ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "${DEP}-${LVER} has no upstream equivalent" | ${TEE} ${LOCKFILE}
			PROGRESS=
		elif [ "${RVER}" != "${LVER}" ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "${DEP}-${LVER} version mismatch, expected ${RVER}" | ${TEE} ${LOCKFILE}
			PROGRESS=
		fi

		AUTOEXPECT=1
		AUTOSET="not set"
		VITAEXPECT=0
		VITASET="set"

		if [ ${DEP} = ${CORE} ]; then
			AUTOEXPECT=0
			AUTOSET="set"
			VITAEXPECT=1
			VITASET="not set"
		elif [ ${DEP} = "pkg" ]; then
			AUTOEXPECT=0
			AUTOSET="set"
		fi

		if [ "${AUTO}" != ${AUTOEXPECT} ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "${DEP}-${LVER} is ${AUTOSET} to automatic" | ${TEE} ${LOCKFILE}
			PROGRESS=
		fi

		if [ "${VITA}" != ${VITAEXPECT} ]; then
			if [ -n "${PROGRESS}" ]; then
				echo | ${TEE} ${LOCKFILE}
			fi
			echo "${DEP}-${LVER} is ${VITASET} to vital" | ${TEE} ${LOCKFILE}
			PROGRESS=
		fi
	done

	if [ -n "${PROGRESS}" ]; then
		echo " done" | ${TEE} ${LOCKFILE}
	fi
}

echo ">>> Root file system: $(mount | awk '$3 == "/" { print $1 }')" | ${TEE} ${LOCKFILE}

if [ -z "${CMD}" -o "${CMD}" = "kernel" ]; then
	set_check kernel
fi

if [ -z "${CMD}" -o "${CMD}" = "base" ]; then
	set_check base
fi

if [ -z "${CMD}" -o "${CMD}" = "repos" ]; then
	echo ">>> Check installed repositories" | ${TEE} ${LOCKFILE}
	(opnsense-verify -l 2>&1) | ${TEE} ${LOCKFILE}
fi

if [ -z "${CMD}" -o "${CMD}" = "plugins" ]; then
	echo ">>> Check installed plugins" | ${TEE} ${LOCKFILE}
	PLUGINS=$(${PKG} query -g '%n %v' 'os-*' 2>&1)
	if [ -n "${PLUGINS}" ]; then
		(echo "${PLUGINS}") | ${TEE} ${LOCKFILE}
	else
		echo "No plugins found." | ${TEE} ${LOCKFILE}
	fi
fi

if [ -z "${CMD}" -o "${CMD}" = "locked" ]; then
	echo ">>> Check locked packages" | ${TEE} ${LOCKFILE}
	LOCKED=$(${PKG} lock -lq 2>&1)
	if [ -n "${LOCKED}" ]; then
		(echo "${LOCKED}") | ${TEE} ${LOCKFILE}
	else
		echo "No locks found." | ${TEE} ${LOCKFILE}
	fi
fi

if [ -z "${CMD}" -o "${CMD}" = "packages" ]; then
	echo ">>> Check for missing package dependencies" | ${TEE} ${LOCKFILE}
	(${PKG} check -dan 2>&1) | ${TEE} ${LOCKFILE}

	echo ">>> Check for missing or altered package files" | ${TEE} ${LOCKFILE}
	(${PKG} check -sa 2>&1) | ${TEE} ${LOCKFILE}
fi

if [ -z "${CMD}" -o "${CMD}" = "core" ]; then
	core_check
fi

output_done
