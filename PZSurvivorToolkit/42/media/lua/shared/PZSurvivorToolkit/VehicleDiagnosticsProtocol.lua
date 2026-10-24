local Protocol = { MODULE = "PZToolkitVehicleTrace" }
function Protocol.request(args)
    return type(args) == "table" and type(args.request) == "number"
        and args.request >= 1 and args.request <= 2147483647 and args.request == math.floor(args.request)
end
function Protocol.status(value)
    return value == "active" or value == "off" or value == "unsupported" or value == "error"
        or value == "unavailable" or value == "denied"
end
return Protocol
