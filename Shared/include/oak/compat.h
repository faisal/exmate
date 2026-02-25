#ifndef COMPAT_H_RD1Z6YZA
#define COMPAT_H_RD1Z6YZA

#include <cstddef>

namespace oak
{
	inline NSOperatingSystemVersion get_os_version ()
	{
		return [NSProcessInfo processInfo].operatingSystemVersion;
	}

	inline size_t os_major () { return get_os_version().majorVersion; }
	inline size_t os_minor () { return get_os_version().minorVersion; }
	inline size_t os_patch () { return get_os_version().patchVersion; }

	inline OSStatus execute_with_privileges (AuthorizationRef authorization, std::string const& pathToTool, AuthorizationFlags options, char* const* arguments, FILE** communicationsPipe)
	{
		// TODO: No modern drop-in replacement exists without SMJobBless/XPC. Migration requires significant redesign.
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		return AuthorizationExecuteWithPrivileges(authorization, pathToTool.c_str(), options, arguments, communicationsPipe);
		#pragma clang diagnostic pop
	}
} /* oak */

#endif /* end of include guard: COMPAT_H_RD1Z6YZA */
