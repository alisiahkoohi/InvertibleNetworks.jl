# Invertible HINT coupling layer from Kruse et al. (2020)
# Author: Philipp Witte, pwitte3@gatech.edu
# Date: January 2020

export CouplingLayerHINT

"""
    H = CouplingLayerHINT(nx, ny, n_in, n_hidden, batchsize; logdet=false, permute="none", k1=1, k2=3, p1=1, p2=0)

 Create a recursive HINT-style invertible layer based on coupling blocks. 

 *Input*: 

 - `nx, ny`: spatial dimensions of input
 
 - `n_in`, `n_hidden`: number of input and hidden channels

 - `logdet`: bool to indicate whether to return the log determinant. Default is `false`.

 - `permute`: string to specify permutation. Options are `"none"`, `"lower"` or `"full"`.

 - `k1`, `k2`: kernel size of convolutions in residual block. `k1` is the kernel of the first and third 
    operator, `k2` is the kernel size of the second operator.

 - `p1`, `p2`: padding for the first and third convolution (`p1`) and the second convolution (`p2`)

 *Output*:
 
 - `H`: Recursive invertible HINT coupling layer.

 *Usage:*

 - Forward mode: `Y = H.forward(X)`

 - Inverse mode: `X = H.inverse(Y)`

 - Backward mode: `ΔX, X = H.backward(ΔY, Y)`

 *Trainable parameters:*

 - None in `H` itself

 - Trainable parameters in coupling layers `H.CL`

 See also: [`CouplingLayerBasic`](@ref), [`ResidualBlock`](@ref), [`get_params`](@ref), [`clear_grad!`](@ref)
"""
struct CouplingLayerHINT <: NeuralNetLayer
    CL::Array{CouplingLayerBasic, 1}
    C::Union{Conv1x1, Nothing}
    logdet::Bool
    forward::Function
    inverse::Function
    backward::Function
end

# Get layer depth for recursion
function get_depth(n_in)
    count = 0
    nc = n_in
    while nc > 4
        nc /= 2
        count += 1
    end
    return count +1
end

# Constructor from input dimensions
function CouplingLayerHINT(nx::Int64, ny::Int64, n_in::Int64, n_hidden::Int64, batchsize::Int64; logdet=false, permute="none", k1=4, k2=3, p1=0, p2=1)

    # Create basic coupling layers
    n = get_depth(n_in)
    CL = Array{CouplingLayerBasic}(undef, n) 
    for j=1:n
        CL[j] = CouplingLayerBasic(nx, ny, Int(n_in/2^j), n_hidden, batchsize; k1=k1, k2=k2, p1=p1, p2=p2, logdet=logdet)
    end

    # Permutation using 1x1 convolution
    if permute == "full"
        C = Conv1x1(n_in)
    elseif permute == "lower"
        C = Conv1x1(Int(n_in/2))
    else
        C = nothing
    end

    return CouplingLayerHINT(CL, C, logdet,
        X -> forward_hint(X, CL, C; logdet=logdet, permute=permute),
        Y -> inverse_hint(Y, CL, C, permute=permute),
        (ΔY, Y) -> backward_hint(ΔY, Y, CL, C, permute=permute)
        )
end

# Input is tensor X
function forward_hint(X::Array{Float32, 4}, CL, C; scale=1, logdet=false, permute="none")
    permute == "full" && (X = C.forward(X))
    Xa, Xb = tensor_split(X)
    permute == "lower" && (Xb = C.forward(Xb))
    if size(X, 3) > 4
        # Call function recursively
        Ya, logdet1 = forward_hint(Xa, CL, C; scale=scale+1, logdet=logdet)
        Y_temp, logdet2 = forward_hint(Xb, CL, C; scale=scale+1, logdet=logdet)
        if logdet==false
            Yb = CL[scale].forward(Y_temp, Xa)[1]
            logdet3 = 0f0
        else
            Yb, logdet3 = CL[scale].forward(Y_temp, Xa)[[1,3]]
        end
        logdet_full = logdet1 + logdet2 + logdet3
    else
        # Finest layer
        Ya = copy(Xa)
        if logdet==false
            Yb = CL[scale].forward(Xb, Xa)[1]
            logdet_full = 0f0
        else
            Yb, logdet_full = CL[scale].forward(Xb, Xa)[[1,3]]
        end
    end
    Y = tensor_cat(Ya, Yb)
    if scale==1 && logdet==false
        return Y
    else
        return Y, logdet_full
    end
end

# Input is tensor Y
function inverse_hint(Y::Array{Float32, 4}, CL, C; scale=1, permute="none")
    Ya, Yb = tensor_split(Y)
    if size(Y, 3) > 4
        Xa = inverse_hint(Ya, CL, C; scale=scale+1)
        Xb = inverse_hint(CL[scale].inverse(Yb, Xa)[1], CL, C; scale=scale+1)
    else
        Xa = copy(Ya)
        Xb = CL[scale].inverse(Yb, Ya)[1]
    end
    permute == "lower" && (Xb = C.inverse(Xb))
    X = tensor_cat(Xa, Xb)
    permute == "full" && (X = C.inverse(X))
    return X
end

# Input are two tensors ΔY, Y
function backward_hint(ΔY::Array{Float32, 4}, Y::Array{Float32, 4}, CL, C; scale=1, permute="none")
    Ya, Yb = tensor_split(Y)
    ΔYa, ΔYb = tensor_split(ΔY)
    if size(Y, 3) > 4
        ΔXa, Xa = backward_hint(ΔYa, Ya, CL, C; scale=scale+1)
        ΔXb, Xb = backward_hint(CL[scale].backward(ΔYb, ΔXa, Yb, Xa)[[1,3]], CL, C; scale=scale+1)
    else
        Xa = copy(Ya)
        ΔXa = copy(ΔYa)
        ΔXb, Xb = CL[scale].backward(ΔYb, ΔYa, Yb, Ya)[[1,3]]
    end
    permute == "lower" && ((ΔXb, Xb) = C.inverse((ΔXb, Xb)))
    ΔX = tensor_cat(ΔXa, ΔXb)
    X = tensor_cat(Xa, Xb)
    permute == "full" && ((ΔX, X) = C.inverse((ΔX, X)))
    return ΔX, X
end

#  Input is tuple single tuple (ΔY, Y)
backward_hint(Y_tuple::Tuple{Array{Float32,4},Array{Float32,4}}, CL, C; scale=1, permute="none") = 
    backward_hint(Y_tuple[1], Y_tuple[2], CL, C; scale=scale, permute=permute)

# Clear gradients
function clear_grad!(H::CouplingLayerHINT)
    for j=1:length(H.CL)
        clear_grad!(H.CL[j])
    end
    typeof(H.C) != nothing && clear_grad!(H.C)
end

# Get parameters
function get_params(H::CouplingLayerHINT)
    nlayers = length(H.CL)
    p = get_params(H.CL[1])
    if nlayers > 1
        for j=2:nlayers
            p = cat(p, get_params(H.CL[j]); dims=1)
        end
    end
    typeof(H.C) != nothing && (p = cat(p, get_params(H.C); dims=1))
    return p
end