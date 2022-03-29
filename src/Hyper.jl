module Hyper

using DocStringExtensions
using hyper_jll
using StringViews

# Enums
include("enum.jl")

# Constants
include("constants.jl")

# Internal structs
include("internal.jl")

# Interfaces
include("interfaces.jl")

# Misc

function version()::String
    return unsafe_string(ccall((:hyper_version, libhyper), Cstring, ()))
end

end
