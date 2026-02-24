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
#warning "AuthorizationExecuteWithPrivileges is deprecated. Consider migrating to XPC service."
		return AuthorizationExecuteWithPrivileges(authorization, pathToTool.c_str(), options, arguments, communicationsPipe);
	}
} /* oak */

#endif /* end of include guard: COMPAT_H_RD1Z6YZA */
