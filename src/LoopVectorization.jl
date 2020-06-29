module LoopVectorization

if (!isnothing(get(ENV, "TRAVIS_BRANCH", nothing)) || !isnothing(get(ENV, "APPVEYOR", nothing))) && isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

using VectorizationBase, SIMDPirates, SLEEFPirates, UnPack, OffsetArrays
using VectorizationBase: REGISTER_SIZE, extract_data, num_vector_load_expr,
    mask, masktable, pick_vector_width_val, valmul, valrem, valmuladd, valmulsub, valadd, valsub, _MM,
    maybestaticlength, maybestaticsize, staticm1, staticp1, staticmul, subsetview, vzero, stridedpointer_for_broadcast,
    Static, Zero, StaticUnitRange, StaticLowerUnitRange, StaticUpperUnitRange, unwrap, maybestaticrange,
    AbstractColumnMajorStridedPointer, AbstractRowMajorStridedPointer, AbstractSparseStridedPointer, AbstractStaticStridedPointer,
    PackedStridedPointer, SparseStridedPointer, RowMajorStridedPointer, StaticStridedPointer, StaticStridedStruct, offsetprecalc,
    maybestaticfirst, maybestaticlast, scalar_less, scalar_greater, noalias!, gesp, gepbyte, pointerforcomparison, NativeTypes, staticmul, staticmuladd
using SIMDPirates: VECTOR_SYMBOLS, evadd, evsub, evmul, evfdiv, vrange, 
    reduced_add, reduced_prod, reduce_to_add, reduced_max, reduced_min, vsum, vprod, vmaximum, vminimum,
    sizeequivalentfloat, sizeequivalentint, vadd!, vsub!, vmul!, vfdiv!, vfmadd!, vfnmadd!, vfmsub!, vfnmsub!,
    vfmadd231, vfmsub231, vfnmadd231, vfnmsub231, sizeequivalentfloat, sizeequivalentint, #prefetch,
    vmullog2, vmullog10, vdivlog2, vdivlog10, vmullog2add!, vmullog10add!, vdivlog2add!, vdivlog10add!, vfmaddaddone
using SLEEFPirates: pow
using Base.Broadcast: Broadcasted, DefaultArrayStyle
using LinearAlgebra: Adjoint, Transpose
using Base.Meta: isexpr
using DocStringExtensions
import LinearAlgebra # for check_args

using Base.FastMath: add_fast, sub_fast, mul_fast, div_fast

export LowDimArray, stridedpointer,
    @avx, @_avx, *ˡ, _avx_!,
    vmap, vmap!, vmapnt, vmapnt!, vmapntt, vmapntt!,
    vfilter, vfilter!, vmapreduce, vreduce

const VECTORWIDTHSYMBOL, ELTYPESYMBOL = Symbol("##Wvecwidth##"), Symbol("##Tloopeltype##")

# redefine without @pure
@inline VectorizationBase.vadd(a::Int64, b::Int64) = llvmcall("%res = add nsw i64 %0, %1\nret i64 %res", Int64, Tuple{Int64,Int64}, a, b)
@inline VectorizationBase.vsub(a::Int64, b::Int64) = llvmcall("%res = sub nsw i64 %0, %1\nret i64 %res", Int64, Tuple{Int64,Int64}, a, b)
@inline VectorizationBase.vmul(a::Int64, b::Int64) = llvmcall("%res = mul nsw i64 %0, %1\nret i64 %res", Int64, Tuple{Int64,Int64}, a, b)
@inline VectorizationBase.vadd(a::Int32, b::Int32) = llvmcall("%res = add nsw i32 %0, %1\nret i32 %res", Int32, Tuple{Int32,Int32}, a, b)
@inline VectorizationBase.vsub(a::Int32, b::Int32) = llvmcall("%res = sub nsw i32 %0, %1\nret i32 %res", Int32, Tuple{Int32,Int32}, a, b)
@inline VectorizationBase.vmul(a::Int32, b::Int32) = llvmcall("%res = mul nsw i32 %0, %1\nret i32 %res", Int32, Tuple{Int32,Int32}, a, b)

@inline VectorizationBase.vleft_bitshift(a::Int64, b::Int64) = llvmcall("%res = shl nsw i64 %0, %1\nret i64 %res", Int64, Tuple{Int64,Int64}, a, b)
@inline VectorizationBase.vleft_bitshift(a::Int32, b::Int32) = llvmcall("%res = shl nsw i32 %0, %1\nret i32 %res", Int32, Tuple{Int32,Int32}, a, b)
for T ∈ [Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float32,Float64]
    for I ∈ [Int32,UInt32,Int64,UInt64]
        @eval @inline VectorizationBase.gep(ptr::Ptr{$T}, i::$I) = $(VectorizationBase.gepquote(T, I, false))
    end
end

"""
REGISTER_COUNT defined in VectorizationBase is supposed to correspond to the actual number of floating point registers on the system.
It is hardcoded into a file at build time.
However, someone may have multiple builds of Julia on the same system, some 32-bit and some 64-bit (e.g., they use 64-bit primarilly,
but keep a 32-bit build on hand to debug test failures on Appveyor's 32-bit build). Thus, we don't want REGISTER_COUNT to be hardcoded
in such a fashion. 
32-bit builds are limited to only 8 floating point registers, so we take care of that here.

If you want good performance, DO NOT use a 32-bit build of Julia if you don't have to.
"""
const REGISTER_COUNT = Sys.ARCH === :i686 ? 8 : VectorizationBase.REGISTER_COUNT

include("vectorizationbase_extensions.jl")
include("predicates.jl")
include("map.jl")
include("filter.jl")
include("costs.jl")
include("operations.jl")
include("graphs.jl")
include("operation_evaluation_order.jl")
include("memory_ops_common.jl")
include("add_loads.jl")
include("add_stores.jl")
include("add_compute.jl")
include("add_constants.jl")
include("add_ifelse.jl")
include("determinestrategy.jl")
include("loopstartstopmanager.jl")
include("lower_compute.jl")
include("lower_constant.jl")
include("lower_memory_common.jl")
include("lower_load.jl")
include("lower_store.jl")
include("lowering.jl")
include("split_loops.jl")
include("condense_loopset.jl")
include("reconstruct_loopset.jl")
include("constructors.jl")
include("user_api_conveniences.jl")
include("mapreduce.jl")
include("broadcast.jl")

"""
LoopVectorization provides macros and functions that combine SIMD vectorization and
loop-reordering so as to improve performance:

- [`@avx`](@ref): transform `for`-loops and broadcasting
- [`@_avx`](@ref): similar to `@avx` but does not use type information
- [`vmap`](@ref) and `vmap!`: vectorized version of `map` and `map!`
- [`vmapnt`](@ref) and `vmapnt!`: non-temporal variants of `vmap` and `vmap!`
- [`vmapntt`](@ref) and `vmapntt!`: threaded variants of `vmapnt` and `vmapnt!`
- [`vfilter`](@ref) and `vfilter!`: vectorized versions of `filter` and `filter!`
"""
LoopVectorization

include("precompile.jl")
_precompile_()

end # module
