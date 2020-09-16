# Tests for invertible neural network module
# Author: Philipp Witte, pwitte3@gatech.edu
# Date: January 2020

using InvertibleNetworks, Test

const group = get(ENV, "GROUP", "all")

# utils
utils = ["test_utils/test_objectives.jl",
          "test_utils/test_nnlib_convolution.jl",
          "test_utils/test_activations.jl",
          "test_utils/test_squeeze.jl"]

# Layers
layers = ["test_layers/test_residual_block.jl",
          "test_layers/test_flux_block.jl",
          "test_layers/test_householder_convolution.jl",
          "test_layers/test_coupling_layer_basic.jl",
          "test_layers/test_coupling_layer_irim.jl",
          "test_layers/test_coupling_layer_glow.jl",
          "test_layers/test_coupling_layer_hint.jl",
          "test_layers/test_coupling_layer_slim.jl",
          "test_layers/test_coupling_layer_slim_learned.jl",
          "test_layers/test_conditional_layer_hint.jl",
          "test_layers/test_conditional_layer_slim.jl",
          "test_layers/test_conditional_res_block.jl",
          "test_layers/test_hyperbolic_layer.jl",
          "test_layers/test_actnorm.jl"]

# Networks
networks = ["test_networks/test_unrolled_loop.jl",
            "test_networks/test_generator.jl",
            "test_networks/test_glow.jl",
            "test_networks/test_hyperbolic_network.jl",
            "test_networks/test_conditional_hint_network.jl"]

# Utils
if group == "all" || group == "utils"
    for t in utils
        @testset  "Test $t" begin
            include(t)
        end
    end
end

# Layers
if group == "all" || group == "layers"
    for t in layers
        @testset  "Test $t" begin
            include(t)
        end
    end
end

# Networks
if group == "all" || group == "networks"
    for t in networks
        @testset  "Test $t" begin
            include(t)
        end
    end
end
