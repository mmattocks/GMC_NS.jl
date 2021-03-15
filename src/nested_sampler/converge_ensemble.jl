"""
    converge_ensemble!(e; max_iterates, backup, clean, converge_criterion, converge_factor, mc_noise, progargs)

Given 'e <: GMC_NS_Ensemble', recursively execute nested sampling steps ('nested_step!()') until ensemble convergence criterion is obtained, or 'max_iterates' is reached. 

Convergence criteria specied by 'converge_criterion <: String': "standard" for evidence convergence, "compression" for ensemble likelihood range compression (can be used to improve MAP parameter estimation after evidence has converged). Factor to use specified by 'converge_factor <: AbstractFloat'. "Standard" defined in Skilling 2006.

For likelihood estimates generated by Monte Carlo model evaluation, 'mc_noise <: AbstractFloat' defines the expected standard deviation of likelihood in the MAP region of parameter space; this will be used as an alternative convergence criterion if the ensemble is converged to within this value.

Keyword arguments to GMC_NS_Progress are passed from progargs.

Skilling, John. “Nested Sampling for Bayesian Computations.” In Proc. Valencia. Benidorm (Alicante, Spain): inference.org.uk, 2006. https://www.inference.org.uk/bayesys/Valencia.pdf.
"""
function converge_ensemble!(e::GMC_NS_Ensemble; max_iterates=typemax(Int64), backup::Tuple{Bool,Integer}=(false,0), clean::Tuple{Bool,Integer,Integer}=(false,0,0),  converge_criterion::String="standard", converge_factor::AbstractFloat=1e-3, mc_noise::AbstractFloat=0., progargs...)
    N = length(e.models); curr_it=length(e.log_Li)

    if curr_it==1 || !isfile(e.path*"/tuner")
        serialize(e.path*"/ens",e)
        tuner_dict=get_tuner_dict(e)
    else
        tuner_dict=deserialize(e.path*"/tuner") #restore tuner from saved if any
    end

    meter = GMC_NS_Progress(e, .1; start_it=curr_it, progargs...)

    converge_check = get_convfunc(converge_criterion)

    reflect_cache = nothing #init cache for models precalculated in galilean reflection

    cln_switch = clean[1] && !e.sample_posterior #ignore clean arguments if posterior samples are to be collected

    while !converge_check(e, converge_factor, mc_noise) && (curr_it <= max_iterates)
        warn, reflect_cache = nested_step!(e, tuner_dict, reflect_cache)
        warn == 1 && (@error "Failed to find new models, aborting at current iterate."; return e)
        curr_it += 1

        backup[1] && curr_it%backup[2] == 0 && e_backup(e,tuner_dict) #every backup interval, serialise the ensemble and tuner
        cln_switch && curr_it%clean[2] == 0 && clean_ensemble_dir(e,clean[3]) #every clean interval, remove old discarded models

        update!(meter, converge_check(e,converge_factor, vals=true)...)
    end

    if converge_check(e,converge_factor, mc_noise)
        final_logZ=measure_evidence(e)
        @info "Job done, sampled to convergence. Final logZ $(final_logZ.val) ± $(final_logZ.err)"

        e_backup(e,tuner_dict) #final backup
        cln_switch && clean_ensemble_dir(e,0) #final clean
        return final_logZ
    elseif curr_it==max_iterates
        @info "Job done, sampled to maximum iterate $max_iterates. Convergence criterion not obtained."

        e_backup(e,tuner_dict) #final backup
        cln_switch && clean_ensemble_dir(e,0) #final clean
        return e.log_Zi[end]
    end
end
                function evidence_converge(e, evidence_fraction, mc_noise=0.; vals=false)
                    mc_noise > 0. && noise_check(e,mc_noise) && return true

                    val=lps(findmax([model.log_Li for model in e.models])[1],  e.log_Xi[end])
                    thresh=lps(log(evidence_fraction),e.log_Zi[end])

                    vals ? (return val, thresh) : (return val<thresh)
                end

                function compress_converge(e, compression_ratio, mc_noise=0.; vals=false)
                    mc_noise > 0. && noise_check(e,mc_noise) && return true
 
                    val=findmax([model.log_Li for model in e.models])[1]-e.contour
                    thresh=compression_ratio

                    val===-Inf && (val=nextfloat(val))
                    vals ? (return val, thresh) : (return val<thresh)
                end

                function get_convfunc(criterion)
                    if criterion == "standard"
                        return evidence_converge
                    elseif criterion == "compression"
                        return compress_converge
                    else
                        throw(ArgumentError("Convergence criterion $criterion not supported! Try \"standard\" or \"compression\"."))
                    end
                end

                #if the entire ensemble is within 99.7% of the noise distribution of its mean likelihood, it is converged to the extent possible given Monte Carlo noise
                function noise_check(e, mc_noise)
                    mod_lhs=[m.log_Li for m in e.models]
                    std(mod_lhs) <= mc_noise ? (return true) : (return false)
                end