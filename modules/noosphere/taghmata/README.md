# Rendered manifests only

The taghmata cluster's sources live in `modules/taghmata`. This directory
holds nothing but `nixidy/manifests`, the rendered copy ArgoCD applies.

It stays here because every ArgoCD Application's source path points at
`modules/noosphere/taghmata/nixidy/manifests/prod/<app>`. Moving it changes
all of those paths at once, with auto-sync and prune on, so it is a
supervised migration of its own and not a file move.
