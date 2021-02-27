using GMC_NS, Distributions

prior=Uniform(0,1)
priors=[prior,prior]

box=[0. 1.
     0. 1.]

gmc=GMC_DEFAULTS
gmc[1]=16
gmc[2]=eps()

e=Eggbox_Ensemble("Eggbox_test", 160, priors, box, gmc...)

uds=Vector{Vector{Function}}([[convergence_display],[evidence_display],[info_display]])

lds=Vector{Vector{Function}}([[ensemble_display]])

converge_ensemble!(e,backup=(true,100),upper_displays=uds, lower_displays=lds, disp_rot_its=1000)