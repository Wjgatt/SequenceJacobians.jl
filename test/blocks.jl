@testset "SimpleBlock" begin
    using SequenceJacobians.RBC
    firm, household, mkt_clearing = RBC.firm, RBC.household, RBC.mkt_clearing
    ins = (:K, :L, :Z, :α, :δ, :K)
    outs = (:r, :w, :Y)
    b = block(firm, (:K, :L, :Z, :α, :δ, lag(:K)), outs)
    @test b isa SimpleBlock
    @test inputs(b) === (ins...,)
    @test ssinputs(b) == Set(ins)
    @test outputs(b) === (outs...,)
    @test b(10.0, 1.0, 1.0, 0.3, 0.05, 10.0) ===
        NamedTuple{outs}(firm(10.0, 1.0, 1.0, 0.3, 0.05, 10.0))

    @test_throws ArgumentError block(firm, (), outs)
    @test_throws ArgumentError block(firm, ins, ())
    @test_throws ArgumentError block(firm, ins, outs, ssins=:n)
    @test_throws ArgumentError block(firm, ins, ins)

    # The input names do not match the functions
    ins = [:K, :K, :L, :w, :eis, :frisch, :φ, :δ]
    outs = [:C, :I]
    b = block(household, [:K, lag(:K), :L, :w, :eis, :frisch, :φ, :δ], outs)
    @test inputs(b) == (ins...,)

    ins = [:r, :r, :C, :C, :Y, :I, :K, :K, :L, :w, :eis, :β]
    outs = [:goods_mkt, :euler, :walras]
    b = block(mkt_clearing,
        [:r, lead(:r), :C, lead(:C), :Y, :I, :K, lag(:K), :L, :w, :eis, :β], outs)
    @test inputs(b) == (ins...,)

    bfirm, bhh, bmkt = rbcblocks()
    varvals = (K=2, L=1, w=1, eis=1, frisch=1, φ=0.9, δ=0.025)
    @test outlength(bfirm, varvals) == 3
    @test outlength(bfirm, varvals, 1) == 1
    varvals = steadystate!(bhh, varvals)
    @test varvals[:C] ≈ 1.1111111111111112
    @test varvals[:I] ≈ 0.05

    aa = ArrayToArgs((1,2,5,6))
    v = rand(6)
    args = aa(v)
    @test args == (v[1], v[2], view(v,3:5), v[6])
    aa2 = ArrayToArgs((3,3,6))
    @test_throws ErrorException aa2(v)

    j = jacobian(bhh, [1,7,8], 5, varvals)
    @test j.J[:,1] ≈ [0, 1]
    @test j.J[:,2] ≈ [0, 2]
    @test j.J[:,3] ≈ [0, -0.975]

    @test sprint(show, bmkt) == "SimpleBlock(mkt_clearing)"
    @test sprint(show, MIME("text/plain"), bmkt) == """
        SimpleBlock(mkt_clearing):
          inputs:  r, C, Y, I, K, L, w, eis, β, lead(C), lag(K), lead(r)
          outputs: goods_mkt, euler, walras"""
    @test sprint(show, j) == "SimpleBlockJacobian(household: K, δ, K → C, I)"
end

@testset "HetBlock" begin
    using SequenceJacobians.KrusellSmith
    ins = (:r, :w, :β, :eis)
    outs = (:A, :C)
    b = kshhblock(0, 200, 500, 0.966, 0.5, 7)
    @test inputs(b) === ins
    @test outputs(b) === outs

    varvals = (r=0.01, w=0.89, β=0.98, eis=1)
    @test outlength(b, varvals) == 2
    @test outlength(b, varvals, 1) == 1
    varvals = steadystate!(b, varvals)
    # Compare results with original Python package
    a = b.ha.a
    @test all(a[1:4,1] .== 0)
    @test all(a[1:3,3] .== 0)
    @test a[5:8,1] ≈ [1.66414395e-3, 3.43258549e-3, 5.22507103e-3, 7.04179415e-3] atol=1e-7
    @test a[1:4,7] ≈ [0.90054142, 0.90383955, 0.90718218, 0.9105699] atol=1e-7
    @test a[end-3:end,7] ≈ [190.6133331, 193.1797762, 195.78086653, 198.41707144] atol=1e-6
    D = b.ha.D
    @test D[1:3,1] ≈ [1.41373523e-2, 4.08282500e-5, 3.83039718e-5] atol=1e-8
    @test D[1:3,4] ≈ [1.42736359e-2, 1.82294210e-2, 2.57256128e-2] atol=1e-8
    @test D[1:3,7] ≈ [3.38553410e-8, 9.33874325e-8, 1.32361967e-7] atol=1e-8
    @test varvals[:C] ≈ 0.9112915134243005 atol=1e-7
    @test varvals[:A] ≈ 2.1291511229699926 atol=1e-7

    # Feed in steady-state values from Python package for comparing results
    varvals = (r=0.01, w=0.89, β=0.981952788061795, eis=1)
    b = kshhblock(0, 200, 500, 0.966, 0.5, 7)
    @test_throws ErrorException jacobian(b, (1,), 5, varvals)
    varvals = steadystate!(b, varvals)
    # Check jacobian for effect on impact
    J = jacobian(b, (1,), 1, varvals)
    j = J.ca
    dv = j.df[:,:,1]
    # Derivatives from Python package are based on a fixed epsilon
    # Need to specify twosided=True for better accuracy
    @test dv[1:3,1] ≈ [4.32936187, 4.20445547, 4.08329971] atol=1e-7
    @test dv[498:500,7] ≈ [0.06198027, 0.06095875, 0.05994965] atol=1e-7
    dev = j.dEVs[1]
    @test dev[1:3,1] ≈ [4.18343962, 4.06543792, 3.95090303] atol=1e-7
    @test dev[498:500,7] ≈ [0.06166387, 0.06064379, 0.05963622] atol=1e-7

    dD = j.dDs[1][:,:,1]
    @test dD[1:3,1] ≈ [-1.22588821e-4, -2.04934264e-5, -5.59833386e-5] atol=1e-9
    @test j.dYs[1] ≈ [3.047070890160419 0.09578625552963749] atol=1e-7

    # Check jacobian for 1-period ahead anticipation effect
    J = jacobian(b, (1,), 2, varvals)
    j = J.ca
    dv = j.df[:,:,1]
    @test dv[1:3,1] ≈ [0, 0, 0]
    @test dv[1:3,5] ≈ [0.89735076, 0.89719971, 0.89689996] atol=1e-7
    @test dv[498:500,7,1] ≈ [0.06039384, 0.05940069, 0.05841955] atol=1e-7
    dev = j.dEVs[1]
    @test dev[1:3,1] ≈ [1.01749209e-4, 1.02397696e-4, 1.02879336e-4] atol=1e-10
    dD = j.dDs[1][:,:,2]
    @test dD[1:3,1] ≈ [-2.45911683e-3,  6.72083192e-4, -3.48413238e-5] atol=1e-10
    @test j.dYs[1][2,:] ≈ [0.6818556801588316, -0.6818556801588341] atol=1e-6

    J = jacobian(b, (1,), 3, varvals)
    j = J.ca
    @test j.Es[1][1:3,1,1] ≈ [-29.52928609, -29.52928582, -29.52928554] atol=1e-7
    @test j.Es[1][498:500,7,2] ≈ [163.33189788, 165.91565888, 168.53432082] atol=1e-7
    @test j.Es[2][1:3,1,1] ≈ [-1.39279428, -1.38938866, -1.38593711] atol=1e-7
    @test j.Es[2][498:500,7,2] ≈ [3.89850409, 3.9474403, 3.99701225] atol=1e-7

    J = jacobian(b, (1,), 5, varvals)
    j = J.ca
    @test j.Js[1][1][1,:] ≈ [3.04707089, 0.68185568, 0.64125217, 0.60439044, 0.57061299] atol=1e-6
    @test j.Js[1][1][5,:] ≈ [2.79839241, 3.42915491, 4.05731394, 4.68424741, 5.31162232] atol=1e-6
    @test j.Js[1][2][1,:] ≈ [0.09578626, -0.68185568, -0.64125217, -0.60439044, -0.57061299] atol=1e-6
    @test j.Js[1][2][5,:] ≈ [0.08926242, 0.12116544, 0.15313027, 0.18541724, 0.21771175] atol=1e-6

    @test sprint(show, b.ha) == "KSHousehold{Float64}"
    @test sprint(show, MIME("text/plain"), b.ha) ==
        "500×7 KSHousehold{Float64} with 1 endogenous state and 1 exogenous state"

    @test sprint(show, b) == "HetBlock(KSHousehold{Float64})"
    @test sprint(show, MIME("text/plain"), b) == """
        HetBlock(KSHousehold{Float64}):
          inputs:  r, w, β, eis
          outputs: A, C"""
    @test sprint(show, J) == "HetBlockJacobian(KSHousehold{Float64}: r → A, C)"
end

@testset "CombinedBlock" begin
    using SequenceJacobians: TwoAsset as ta
    ins0 = (:pip, :mc, :r, :Y, :κp, :mup, :εmup, lead(:Y), lead(:pip), lead(:r))
    outs = :pip
    bpricing = block(ta.pricing, ins0, :nkpc)
    mpricing = model(bpricing)
    sspricing = SteadyState(mpricing,
        [:mc=>0.985, :r=>0.0125, :Y=>1, :κp=>0.1, :mup=>1.015228426395939, :εmup=>0],
        :pip=>0.1, :nkpc=>0)
    ins = (:mc, :r, :Y, :κp, :mup)
    @test_throws ArgumentError block(sspricing, ins, outs)
    @test_throws ArgumentError block(sspricing, ins0, outs, solver=Roots_Default)
    b = block(sspricing, ins, outs, solver=Roots_Default)
    @test inputs(b) == ins
    @test invars(b) == ins
    @test ssinputs(b) == Set(ins)
    @test outputs(b) == (:pip,)
    varvals0 = NamedTuple() # Not the actual varvals used by CombinedBlock
    @test outlength(b, varvals0) == 1
    @test outlength(b, varvals0, 1) == 1
    @test model(b) === mpricing
    varvals = sspricing[]
    steadystate!(b, varvals)
    @test b.ss[:pip] ≈ 0 atol=1e-8
    @test b.ss[:nkpc] ≈ 0 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 1:length(ins), 3, varvals)
    @test all(isapprox.(J.Gs[:κp][:pip].out, 0, atol=1e-8))
    Jmc = [0.1 0.09876543 0.09754611;
           0   0.1        0.09876543;
           0   0          0.1        ]
    @test J.Gs[:mc][:pip].out ≈ Jmc atol=1e-8
    Jmup = [0.0970225 0.09582469 0.09464167;
            0         0.0970225  0.09582469;
            0         0          0.0970225  ]
    @test J.Gs[:mup][:pip].out ≈ Jmup atol=1e-8
    @test all(isapprox.(J.Gs[:Y][:pip].out, 0, atol=1e-8))
    @test all(isapprox.(J.Gs[:r][:pip].out, 0, atol=1e-8))

    ins0 = (:p, :div, :r, lead(:div), lead(:p), lead(:r))
    outs = :p
    barbitrage = block(ta.arbitrage, ins0, :equity)
    ins = (:div, :r)
    b = block(barbitrage, ins, outs, [:div=>0.14, :r=>0.0125], :p=>10, :equity=>0,
        solver=Brent(), ssargs=(:x0=>(5,15),))
    varvals = steadystate!(b, b.ss[])
    @test b.ss[:p] ≈ 11.2 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 1:length(ins), 3, varvals)
    Jdiv = [0 0.98765432 0.97546106;
            0 0          0.98765432;
            0 0          0          ]
    @test J.Gs[:div][:p].out ≈ Jdiv atol=1e-8
    Jr = [0 -11.0617284 -10.92516385;
          0 0           -11.0617284;
          0 0           0            ]
    @test J.Gs[:r][:p].out ≈ Jr atol=1e-6

    blabor = block(ta.labor, (:Y, :w, :K, :Z, :α, lag(:K)), (:N, :mc))
    ins0 = [:Q, :K, :r, :N, :mc, :Z, :δ, :εI, :α, :εr, lag(:K), lead(:K), lead(:N), lead(:Q), lead(:Z), lead(:mc), lead(:r)]
    binvest = block(ta.investment, ins0, [:inv, :val])
    calis = [:Y, :w, :Z, :α, :r, :δ, :εI, :εr]
    b = block([blabor, binvest], [:Y, :w, :Z, :r], [:Q, :K, :N, :mc],
        calis.=>[1.0, 0.66, 0.4677898145312322, 0.3299492385786802, 0.0125, 0.02, 4, 0],
        [:Q=>2, :K=>11], [:inv, :val].=>0.0, solver=Hybrid)
    varvals = steadystate!(b, b.ss[])
    @test varvals[:Q] ≈ 1 atol=1e-8
    @test varvals[:K] ≈ 10 atol=1e-8

    # Compare results with original Python package
    J = jacobian(b, 1:4, 3, varvals)
    Jyk = [0 0.03789632 0.03714605;
           0 0.03761037 0.07490055;
           0 0.03746678 0.0746146  ]
    @test J.Gs[:Y][:K].out ≈ Jyk atol=1e-7
    Jrq = [0 -0.97663311 -0.95729755;
           0 0.00736934  -0.97297837;
           0 0.00370042   0.00736934 ]
    @test J.Gs[:r][:Q].out ≈ Jrq atol=1e-6

    @test sprint(show, b) ==
        "CombinedBlock(Hybrid, SimpleBlock(labor), SimpleBlock(investment))"
    @test sprint(show, MIME("text/plain"), b) == """
        CombinedBlock(Hybrid) with 2×2 SteadyState{Float64} and 2 GE restrictions:
          inputs:  Y, w, Z, r
          outputs: Q, K, N, mc
          blocks:  SimpleBlock(labor), SimpleBlock(investment)"""
    @test sprint(show, J) == "CombinedBlockJacobian(val, inv: Y, w, Z, r → Q, K, N, mc)" ||
        sprint(show, J) == "CombinedBlockJacobian(inv, val: Y, w, Z, r → Q, K, N, mc)"

    b = block([blabor], [:Y, :w, :Z], [:N, :mc],
        [:Y, :w, :K, :Z, :α].=>[1.0, 0.66, 10, 0.4677898145312322, 0.3299492385786802])
    J = jacobian(b, 1:3, 3, varvals)
    bj = jacobian(blabor, 1:3, 3, varvals)
    @test J[1,1] ≈ bj[1,1](3) atol=1e-6
    @test J[2,2] ≈ bj[2,2](3) atol=1e-6
    varvals2 = merge(varvals, (α=0.5,))
    J(varvals2)
    bj(varvals2)
    @test J[1,1] ≈ bj[1,1](3) atol=1e-6
    @test J[2,2] ≈ bj[2,2](3) atol=1e-6

    b2 = block([blabor, binvest], [:Y, :w, :Z], [:N, :mc, :inv],
        [:Y, :w, :K, :Z, :α, :Q, :r, :δ, :εI, :εr].=>
        [1.0, 0.66, 10, 0.4677898145312322, 0.3299492385786802, 1, 0.0125, 0.02, 4, 0])
    J2 = jacobian(b2, 1:3, 3, varvals, dZs=(:w=>[0.1,0.05,0.0], :Z=>[0.1,0.05,0.0]))
    J2(varvals2)
    @test J[1,1] ≈ bj[1,1](3) atol=1e-6
    u = PEImpulseUpdate(J2, :α, [:w, :Z], [:N, :mc], 3)
    u((α=0.5,))
    J2(varvals2)
    @test u.vals[:,2,1] ≈ J2[2,2]

    @test sprint(show, b) == "CombinedBlock(NoRootSolver, SimpleBlock(labor))"
    @test sprint(show, MIME("text/plain"), b) == """
        CombinedBlock(NoRootSolver) with 0×0 SteadyState{Float64} and 0 GE restriction:
          inputs:  Y, w, Z
          outputs: N, mc
          block:  SimpleBlock(labor)"""
    @test sprint(show, J) == "PECombinedBlockJacobian(Y, w, Z → N, mc)"
end

@testset "WrappedBlock" begin
    using SequenceJacobians: SmetsWouters as sw
    blk = sw.wage_markup_blk()
    vals = sw.swparams(sw.default_params)
    vals = (vals..., c=0.0, n=0.0, w=0.0, μw=0.0)
    jac = jacobian(blk, (1,2), 300, vals)
    b = wrap(blk, jac)
    @test inputs(b) == inputs(blk)
    @test invars(b) == invars(blk)
    @test ssinputs(b) == ssinputs(blk)
    @test outputs(b) == outputs(blk)
    @test outlength(b, vals) == outlength(blk, vals)
    @test outlength(b, vals, 1) == outlength(blk, vals, 1)

    steadystate!(blk, vals)

    @test sprint(show, b) == "WrappedBlock(SimpleBlock(wage_markup))"
    @test sprint(show, MIME("text/plain"), b) == """
        WrappedBlock(SimpleBlock(wage_markup)):
          inputs:  c, n, w, λc, γ, σl, lag(c)
          outputs: μw"""
end
