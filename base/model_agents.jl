
include("world_path_util.jl")


# *********
# decisions
# *********


"Quality of a link `link` to location `loc`. Calls `quality(::Infolocation,...)`."
function quality(link :: InfoLink, loc :: InfoLocation, par)
	#@assert known(link)
	#@assert known(loc)
	#@assert friction(link) >= 0
	#@assert !isnan(friction(link))
	# [0:3]					     [0:1.5], [0:15]	
	quality(loc, par) / (1.0 + friction(link)*par.qual_weight_frict)
end

"Quality of location `loc`."
function quality(loc :: InfoLocation, par)
	# [0:1]
	discounted(loc.quality) + 
		# [0:1]
		loc.pos.x * par.qual_weight_x + 
		# [0:1]
		discounted(loc.resources) * par.qual_weight_res
end

# TODO properties of waystations
#"Quality of a plan consisting of a sequence of locations."
#function quality(plan :: Vector{InfoLocation}, par)
#	if length(plan) == 2
#		return quality(find_link(plan[2], plan[1]), plan[1], par)
#	end
#
#	# start out with quality of target
#	q = quality(plan[1],  par)
#
#	f = 0.0
#	for i in 1:length(plan)-1
#		f += find_link(plan[i], plan[i+1]).friction.value
#	end
#
#	q / (1.0 + f * par.qual_weight_frict)
#end


#function costs_quality(loc :: InfoLocation, par)
#	(par.path_weight_frict + 3.0) / 
#		(par.path_weight_frict + quality(loc, par))
#end

# TODO this should be affected by trust as well
#function costs_quality(link :: InfoLink, loc :: InfoLocation, par)
#	friction(link) * costs_quality(loc, par)
#end

#"Movement costs from `l1` to `l2`, taking into account `l2`'s quality."
#function costs_quality(l1::InfoLocation, l2::InfoLocation, par)
#	link = find_link(l1, l2)
#	costs_quality(link, l2, par)
#end

#function costs_quality(plan :: Vector{InfoLocation}, par)
#	c = 0.0
#	for i in 1:length(plan)-1
#		# plan is sorted in reverse (target sits at 1)
#		c += costs_quality(plan[i+1], plan[i], par)
#	end
#	c
#end


#function make_plan!(agent, par)
#	if agent.info_target == []
#		agent.plan = []
#	else
#		if par.path_use_quality
#			agent.plan, count = Pathfinding.path_Astar(info_current(agent), agent.info_target, 
#			(l1, l2)->costs_quality(l1, l2, par), path_costs_estimate, each_neighbour)
#		else
#			agent.plan, count = Pathfinding.path_Astar(info_current(agent), agent.info_target, 
#				path_costs, path_costs_estimate, each_neighbour)
#		end
#	end
#end

#function plan_costs!(agent, par)
#	make_plan!(agent, par)
#
#	if agent.plan != []
#		agent.planned += 1
#		return agent
#	end
#
#	loc = info_current(agent)
#
#	if length(loc.links) == 0
#		return agent
#	end
#
#	quals = Float64[]
#	sizehint!(quals, length(loc.links))
#	prev = 0.0
#
#	for l in loc.links
#		c = costs_quality(l, otherside(l, loc), par) + 0.000001
#		#@assert friction(loc.links[i]) > 0
#		#@assert !isnan(c)
#		#@assert c > 0
#		push!(quals, 1.0/c + prev)
#		prev = quals[end]
#	end
#
#	best = 0
#	if quals[end] > 0.0
#		r = rand() * (quals[end] - 0.000001)
#		best = findfirst(x -> x>r, quals)
#	end
#
#	# go to best neighbouring location 
#	agent.plan = [otherside(loc.links[best], loc), loc]
#
#	agent
#end


#function plan_old!(agent, par)
#	make_plan!(agent, par)
#
#	loc = info_current(agent)
#
#	quals = fill(0.0, length(loc.links)+1)
#	quals[1] = quality(loc, par)
#
#	for i in eachindex(loc.links)
#		q = quality(loc.links[i], otherside(loc.links[i], loc), par)
#		@assert !isnan(q)
#		quals[i+1] = quals[i] + q
#	end
#
#	# plan goes into the choice as well
#	if agent.plan != []
#		push!(quals, quality(agent.plan, par) + quals[end])
#	end
#
#	best = 0
#	if quals[end] > 0
#		r = rand() * (quals[end] - 0.0001)
#		# -1 because first el is stay
#		best = findfirst(x -> x>r, quals) - 1
#	end
#
#	if best == length(quals) - 1 && agent.plan != []
#		agent.planned += 1
#	end
#
#	# either stay or use planned path
#	if best == 0 ||
#		(best == length(quals) - 1 && agent.plan != [])
#		return agent
#	end
#
#	# go to best neighbouring location 
#	agent.plan = [otherside(loc.links[best], loc), loc]
#
#	agent
#end


function plan_simple!(agent, par)
	loc = info_current(agent)

	quals = fill(0.0, length(loc.links))

	for i in eachindex(loc.links)
		q = quality(loc.links[i], otherside(loc.links[i], loc), par)
		@assert !isnan(q)
		quals[i] = q + (i > 1 ? quals[i-1] : 0.0)
	end

	if quals[end] > 0
		r = rand() * (quals[end] - 0.0001)
		# -1 because first el is stay
		best = findfirst(x -> x>r, quals)
	end

	agent.next = otherside(loc.links[best], loc)
end


#function decide_move(agent::Agent, world::World, par)
	# end is current location
#	info2real(agent.plan[end-1])
#end


# ***********
# exploration
# ***********


# explore while moving one step
#function explore_move!(agent, world, dest, par)
#	info_loc2 :: InfoLocation, l = explore_at!(agent, world, dest, par.speed_expl_move, false, par)
#	info_loc1 :: InfoLocation = info_current(agent)
#
#	link = find_link(agent.loc, dest)
#	inf = info(agent, link)
#	if !known(inf)
#		# TODO stochastic error
#		inf = discover!(agent, link, agent.loc, par)
#	end
#
#	inf.friction = TrustedF(link.friction, par.trust_travelled)
#
#	agent
#end


# connect loc and link (if not already connected)
function connect!(loc :: InfoLocation, link :: InfoLink)
	# add location to link
	if link.l1 != loc && link.l2 != loc
		# link not connected yet, should have free slot
		if !known(link.l1)
			link.l1 = loc
		elseif !known(link.l2)
			link.l2 = loc
		else
			error("Error: Trying to connect a fully connected link!")
		end
	end

	# add link to location
	if ! (link in loc.links)
		add_link!(loc, link)
	end
end


# add new location to agent (based on world info)
# connect to existing links
function discover!(agent, loc :: Location, par)
	# agents start off with expected values
	inf = InfoLocation(loc.pos, loc.id, TrustedF(par.res_exp), TrustedF(par.qual_exp), [])
	# add location info to agent
	add_info!(agent, inf, loc.typ)
	# connect existing link infos
	for link in loc.links
		info_link = info(agent, link)

		# links to exit are always known
		if !known(info_link)
			if loc.typ != EXIT
				lo = otherside(link, loc)
				if lo.typ == EXIT && knows(agent, lo)
					discover!(agent, link, loc, par)
				end
			end
		# connect known links
		else				
			connect!(inf, info_link)
		end
	end

	inf	
end	


# add new link to agent (based on world info)
# connect to existing location
function discover!(agent, link :: Link, from :: Location, par)
	info_from = info(agent, from)
	@assert known(info_from)
	info_to = info(agent, otherside(link, from))
	frict = link.distance * par.frict_exp[Int(link.typ)]
	@assert frict > 0
	info_link = InfoLink(link.id, info_from, info_to, TrustedF(frict))
	add_info!(agent, info_link)
	# TODO lots of redundancy, possibly join/extend
	connect!(info_from, info_link)
	if known(info_to)
		connect!(info_to, info_link)
	end

	info_link	
end


#function current_quality(loc :: Location, par)  
#	(loc.quality + loc.traffic * par.weight_traffic) / (1.0 + loc.traffic * par.weight_traffic)
#end

function explore_at!(agent, world, loc :: Location, speed, allow_indirect, par)
	# knowledge
	inf = info(agent, loc)
	
	if !known(inf)
		inf = discover!(agent, loc, par)
	end

	# gain information on local properties
	# stochasticity?
	inf.resources = update(inf.resources, loc.resources, speed)
	inf.quality = update(inf.quality, loc.quality, speed)
	#inf.quality = update(inf.quality, current_quality(loc, par), speed)

	# only location, no links, done
	if ! allow_indirect
		return inf, loc
	end

	# gain info on links and linked locations
	
	for link in loc.links
		info_link = info(agent, link)

		if !known(info_link) && rand() < par.p_find_links
			info_link = discover!(agent, link, loc, par)

			#info_link.friction = TrustedF(link.friction, par.trust_found_links)
			info_link.friction = update(info_link.friction, link.friction, speed)
			
			# no info, but position is known
			explore_at!(agent, world, otherside(link, loc), 0.0, false, par)
		end

		# we might get info on connected location
		if known(info_link) && rand() < par.p_find_dests
			explore_at!(agent, world, otherside(link, loc), 0.5 * speed, false, par)
		end
	end

	inf, loc
end


# ********************
# information exchange
# ********************

# add new link as a copy from existing one (from other agent)
# currently requires that both endpoints are known
function maybe_learn!(agent, link_orig :: InfoLink)
	# get corresponding loc info from naive individual
	l1_info = agent.info_loc[link_orig.l1.id] 
	l2_info = agent.info_loc[link_orig.l2.id] 

	# check if the agent knows both end points, otherwise abort
	if !known(l1_info) || !known(l2_info)
		return UnknownLink	
	end

	info_link = InfoLink(link_orig.id, l1_info, l2_info, link_orig.friction)
	add_info!(agent, info_link)
	connect!(l1_info, info_link)
	connect!(l2_info, info_link)

	info_link
end


#function consensus(val1::TrustedF, val2::TrustedF) :: TrustedF
#	sum_t = max(val1.trust + val2.trust, 0.0001)
#	v = (discounted(val1) + discounted(val2)) / sum_t
#	t = max(val1.trust, val2.trust)
#
#	TrustedF(v, t)
#end


struct InfoPars
	convince :: Float64
	convert :: Float64
	confuse :: Float64
	error :: Float64
end


function receive_belief(self::TrustedF, other::TrustedF, par)
	ci = par.convince
	ce = par.convert 
	cu = par.confuse

	t = self.trust		# trust
	d = 1.0 - t		# doubt
	v = self.value

	# perceived values after error
	t_pcv = limit(0.000001, other.trust + unf_delta(par.error), 0.99999)
	d_pcv = 1.0 - t_pcv
	v_pcv = max(0.0, other.value + unf_delta(par.error))
	
	dist_pcv = abs(v-v_pcv) / (v + v_pcv + 0.00001)

	# sum up values according to area of overlap between 1 and 2
	# from point of view of 1:
	# doubt x doubt -> doubt
	# trust x doubt -> trust
	# doubt x trust -> doubt / convince
	# trust x trust -> trust / convert / confuse (doubt)

	#					doubt x doubt		doubt x trust
	d_ = 					d * d_pcv + 	d * t_pcv * (1.0 - ci) + 
	#	trust x trust
		t * t_pcv * cu * dist_pcv
	#	trust x doubt
	v_ = t * d_pcv * v + 					d * t_pcv * ci * v_pcv + 
		t * t_pcv * (1.0 - cu * dist_pcv) * ((1.0 - ce) * v + ce * v_pcv)

	limit(0.000001, d_, 0.99999), v_
end

function exchange_beliefs(val1::TrustedF, val2::TrustedF, par1, par2)
	if val1.trust == 0.0 && val2.trust == 0.0
		return val1, val2
	end

	d1_, v1_ = receive_belief(val1, val2, par1)

	d2_, v2_ = receive_belief(val2, val1, par2)

	TrustedF(v1_ / (1.0-d1_), 1.0 - d1_), TrustedF(v2_ / (1.0-d2_), 1.0 - d2_)
end


function exchange_info!(a1::Agent, a2::Agent, world::World, par)
	# a1 can never have arrived yet
	arr = arrived(a2)

	p2 = InfoPars(par.convince, par.convert, par.confuse, par.error)
	# values a1 experiences, have to be adjusted if a2 has already arrived
	p1 = if arr	
		InfoPars(par.convince^(1.0/par.weight_arr), par.convert^(1.0/par.weight_arr), par.confuse, 
			par.error)
		else
			p2
		end

	for l in eachindex(a1.info_loc)
		if rand() > par.p_transfer_info
			continue
		end
		
		info1 :: InfoLocation = a1.info_loc[l]
		info2 :: InfoLocation = a2.info_loc[l]

		# neither agent knows anything
		if !known(info1) && !known(info2)
			continue
		end
		
		loc = world.cities[l]

		if !known(info1)
			discover!(a1, loc, par)
		elseif !known(info2) && !arr
			discover!(a2, loc, par)
		end

		# both have knowledge at l, compare by trust and transfer accordingly
		if known(info1) && known(info2)
			res1, res2 = exchange_beliefs(info1.resources, info2.resources, p1, p2)
			qual1, qual2 = exchange_beliefs(info1.quality, info2.quality, p1, p2)
			info1.resources = res1
			info1.quality = qual1
			# only a2 can have arrived
			if !arr 
				info2.resources = res2
				info2.quality = qual2
			end
		end
	end

	for l in eachindex(a1.info_link)
		if rand() > par.p_transfer_info
			continue
		end
		
		info1 :: InfoLink = a1.info_link[l]
		info2 :: InfoLink = a2.info_link[l]

		# neither agent knows anything
		if !known(info1) && !known(info2)
			continue
		end

		link = world.links[l]
		
		# only one agent knows the link
		if !known(info1)
			if knows(a1, link.l1) && knows(a1, link.l2)
				discover!(a1, link, link.l1, par)
			end
		elseif !known(info2) && !arr
			if knows(a2, link.l1) && knows(a2, link.l2)
				discover!(a2, link, link.l1, par)
			end
		end
		
		# both have knowledge at l, compare by trust and transfer accordingly
		if known(info1) && known(info2)
			#@assert info1.friction.value > 0
			#@assert info2.friction.value > 0
			frict1, frict2 = exchange_beliefs(info1.friction, info2.friction, p1, p2)
			#@assert frict1.value > 0 "$(info1.friction.value), $(info1.friction.trust), $(info2.friction.value), $(info2.friction.trust)"
			#@assert frict2.value > 0
			info1.friction = frict1
			if !arr
				info2.friction = frict2
			end
		end
	end
end



# ********
# contacts
# ********


# TODO NOT USED
#function  step_agent_contacts!(agent, par)
#	for i in length(agent.contacts):-1:1
#		if rand() < par.p_drop_contact
#			drop_at!(agent.contacts, i)
#		end
#	end
#end

maxed(agent, par) = length(agent.contacts) >= par.n_contacts_max

# *********************
# event functions/rates
# *********************

# we use 1 here as agent.next might be the agent's current location
function move_rate(agent, par)
	loc = info_current(agent)

	qs = mapreduce(+, loc.links) do l
			quality(l, otherside(l, loc), par)
		end

	qs2 = mapreduce(+, loc.links) do l
			quality(l, otherside(l, loc), par)^2
		end
	
	q = quality(loc, par)

	if qs == 0.0
		return 0.0
	end

	q > 0.0 ? qs2/(q * qs) : 1.0
end


# same as ML3
transit_rate(agent, par) = 1.0

rate_contacts(agent, par) = length(agent.contacts) * par.p_keep_contact

rate_talk(agent, par) = length(agent.contacts) * par.p_info_contacts



function costs_stay!(agent, par)
	agent.capital += par.ben_resources * agent.loc.resources - par.costs_stay

	agent
end

# explore while staying at a location
function explore_stay!(agent, world, par)
	explore_at!(agent, world, agent.loc, par.speed_expl_stay, true, par)

	agent
end

function meet_locally!(agent, world, par)
	pop = agent.loc.people

	# agents might have left in the meantime
	if length(pop) == 1
		return agent
	end

	while (a = rand(pop)) == agent end

	add_contact!(agent, a)
	if !maxed(a, par)
		add_contact!(a, agent)
	end

	exchange_info!(agent, a, world, par)

	agent
end

function talk_once!(agent, world, par)
	exchange_info!(agent, rand(agent.contacts), world, par)

	agent
end

function costs_move!(agent, link :: Link, par)
	agent.capital -= par.costs_move * link.friction

	agent
end


function start_move!(agent, world, par)
	agent.in_transit = true

	plan_simple!(agent, par)

	loc = info2real(agent.next, world)
	link = find_link(agent.loc, loc)
	
	# update traffic counter
	link.count += 1
	agent.steps += 1

	costs_move!(agent, link, par)

	agent
end


function finish_move!(agent, world, par)
	agent.in_transit = false

	loc = info2real(agent.next, world)
	move!(world, agent, loc)

	if arrived(agent)
		return nothing
	end

	agent
end


