"""Construct the research-only candidate from one exact external source."""
import hashlib

PERMISSIONS_SHA256 = "27def55fa7ed50eda0554f0c5d248ee37352066f663f3e1c16cfed529e97b409"
FIELDS = ("ProximityEnabled", "ForceCorpseOnly", "AllowToggleProximity", "AllowSwitchMode", "AutoLockEnabled", "AllowToggleAutoLock")


def candidate(source: bytes) -> str:
    if hashlib.sha256(source).hexdigest() != PERMISSIONS_SHA256:
        raise ValueError("Unsupported BetterContainers Permissions.lua")
    text = source.decode().replace("\r\n", "\n")
    prefix, compute = text.split("function Permissions.compute(options)", 1)
    body, suffix = compute.rsplit("\nreturn Permissions", 1)
    body = body.replace("    options = options or {}", "    if Permissions.getSandbox ~= originalGetSandbox then return originalCompute(options) end\n    options = options or {}", 1)
    before, rest = body.split("    local sb = Permissions.getSandbox()", 1)
    for field in FIELDS:
        rest = rest.replace("sb." + field, "sb_" + field)
    locals_ = "\n" + "\n".join("    local sb_" + field + " = sb." + field for field in FIELDS)
    optimized = before + "    local sb = Permissions.getSandbox()" + locals_ + rest
    return (text.rsplit("\nreturn Permissions", 1)[0] + "\nlocal originalCompute = Permissions.compute\nlocal originalGetSandbox = Permissions.getSandbox\nfunction Permissions.compute(options)" + optimized + "\nreturn Permissions\n")
