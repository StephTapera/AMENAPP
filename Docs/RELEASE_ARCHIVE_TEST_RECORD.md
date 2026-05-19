# Amen Release Archive Test Record

This record proves the App Store build was archived and tested against the intended backend configuration.

## Machine-Checked Markers

```text
RELEASE_ARCHIVE_CREATED=false
RELEASE_ARCHIVE_TESTED=false
RELEASE_ARCHIVE_SCHEME=
RELEASE_ARCHIVE_CONFIGURATION=Release
RELEASE_ARCHIVE_BUILD_NUMBER=
RELEASE_ARCHIVE_TEST_DEVICE_OR_SIMULATOR=
RELEASE_ARCHIVE_OWNER=
RELEASE_ARCHIVE_DATE=
```

## Required Release Build Checks

- [ ] Xcode archive created with the App Store signing identity/team.
- [ ] Build uses production or approved staging Firebase configuration.
- [ ] No debug endpoints or production mocks are enabled.
- [ ] Login, logout, delete account, report, block, media upload, AI request, privacy settings, and purchase flows are smoke tested as applicable.
- [ ] Push notification content does not expose sensitive private data.
- [ ] App Store privacy labels and review notes match the archived build.
- [ ] Crash-free smoke test completed on at least one physical device.
