
function [bestmem,bestval,nfeval,cpu_time,conv_curve,pop]=DiffEvol(fname,inputs,results,privstruct);
 
%********************************************************************************
% DiffEvol: modification of DEVEC(storn@icsi.berkeley.edu) by E. Balsa-Canto
%          - arguments have been modified     
%          - changes on the generation of initial population 
%             depending on new input VAR. Note that if VAR>=1 
%             population is generated as in original DE version
%          -  changes on function. Vector g is dummy for unconstrained
%             cases
%          -  extra convergence criteria based on population variability
%          -  some vectorized operations to reduce computational cost
%          -  includes prior modifications by J.R. Banga regarding bounds
%             checking and forcing  and initial guess
%********************************************************************************             
% 
% GENERAL DESCRIPTION OF DIFFERENTIAL EVOLUTION
%
% minimization of a user-supplied function with respect to x(1:D),
% using the differential evolution (DE) algorithm of Rainer Storn
% (http://www.icsi.berkeley.edu/~storn/code.html)
% 
% Special thanks go to Ken Price (kprice@solano.community.net) and
% Arnold Neumaier (http://solon.cma.univie.ac.at/~neum/) for their
% valuable contributions to improve the code.
% % Strategies with exponential crossover, further input variable
% tests, and arbitrary function name implemented by Jim Van Zandt 
% <jrv@vanzandt.mv.com>, 12/97.
%
% Output arguments:
% ----------------
% bestmem        parameter vector with best solution
% bestval        best objective function value
% nfeval         number of function evaluations
%
% Input arguments:  
% ---------------
%
% fname          string naming a function f(x,y) to minimize
% VTR            "Value To Reach". devec3 will stop its minimization
%                if either the maximum number of iterations "itermax"
%                is reached or the best parameter vector "bestmem" 
%                has found a value f(bestmem,y) <= VTR.
% D              number of parameters of the objective function 
% XVmin          vector of lower bounds XVmin(1) ... XVmin(D)
%                of initial population
%                *** note: these are not bound constraints!! ***
% XVmax          vector of upper bounds XVmax(1) ... XVmax(D)
%                of initial population
% y		        problem data vector (must remain fixed during the
%                minimization)
% NP             number of population members
% itermax        maximum number of iterations (generations)
% F              DE-stepsize F from interval [0, 2]
% CR             crossover probability constant from interval [0, 1]
% strategy       1 --> DE/best/1/exp           6 --> DE/best/1/bin
%                2 --> DE/rand/1/exp           7 --> DE/rand/1/bin
%                3 --> DE/rand-to-best/1/exp   8 --> DE/rand-to-best/1/bin
%                4 --> DE/best/2/exp           9 --> DE/best/2/bin
%                5 --> DE/rand/2/exp           else  DE/rand/2/bin
%                Experiments suggest that /bin likes to have a slightly
%                larger CR than /exp.
% refresh        intermediate output will be produced after "refresh"
%                iterations. No intermediate output will be produced
%                if refresh is < 1
%
%       The first four arguments are essential (though they have
%       default values, too). In particular, the algorithm seems to
%       work well only if [XVmin,XVmax] covers the region where the
%       global minimum is expected. DE is also somewhat sensitive to
%       the choice of the stepsize F. A good initial guess is to
%       choose F from interval [0.5, 1], e.g. 0.8. CR, the crossover
%       probability constant from interval [0, 1] helps to maintain
%       the diversity of the population and is rather uncritical. The
%       number of population members NP is also not very critical. A
%       good initial guess is 10*D. Depending on the difficulty of the
%       problem NP can be lower than 10*D or must be higher than 10*D
%       to achieve convergence.
%       If the parameters are correlated, high values of CR work better.
%       The reverse is true for no correlation.
%
% About devec3.m
% --------------
% Differential Evolution for MATLAB
% Copyright (C) 1996, 1997 R. Storn
% International Computer Science Institute (ICSI)
% 1947 Center Street, Suite 600
% Berkeley, CA 94704
% E-mail: storn@icsi.berkeley.edu
% WWW:    http://http.icsi.berkeley.edu/~storn
%
% devec is a vectorized variant of DE which, however, has a
% propertiy which differs from the original version of DE:
% 1) The random selection of vectors is performed by shuffling the
%    population array. Hence a certain vector can't be chosen twice
%    in the same term of the perturbation expression.
%
% Due to the vectorized expressions devec3 executes fairly fast
% in MATLAB's interpreter environment.
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 1, or (at your option)
% any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details. A copy of the GNU 
% General Public License can be obtained from the 
% Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA


init_time=cputime;

%-----Check input variables---------------------------------------------

err=[];

VTR=inputs.nlpsol.DE.VTR;
D=size(inputs.nlpsol.vguess,2);
x0=inputs.nlpsol.vguess;
XVmin=inputs.nlpsol.vmin;
XVmax=inputs.nlpsol.vmax;
NP=inputs.nlpsol.DE.NP;
itermax=inputs.nlpsol.DE.itermax;
cvarmax=inputs.nlpsol.DE.cvarmax;
F=inputs.nlpsol.DE.F;
CR=inputs.nlpsol.DE.CR;
strategy=inputs.nlpsol.DE.strategy;
refresh=inputs.nlpsol.DE.refresh;
var=inputs.nlpsol.DE.var;

if isempty(NP)
    NP=20*D;
end

if (NP < 5)
  NP=5;
   fprintf(1,' NP increased to minimal value 5\n');
end
if ((CR < 0) | (CR > 1))
   CR=0.5;
   fprintf(1,'CR should be from interval [0,1]; set to default value 0.5\n');
end
if (itermax <= 0)
   itermax = 200;
   fprintf(1,'itermax should be > 0; set to default value 200\n');
end
refresh = floor(refresh);
%--------------------------------------------------------------------------

%-----Initialize population and some arrays-------------------------------
pop = zeros(NP,D); %initialize pop to gain speed
popold    = zeros(size(pop));     % toggle population
val       = zeros(1,NP);          % create and reset the "cost array"
g         = zeros(1,NP);          % create and reset the "constraints array"
index     = zeros(1,NP);
bestmem   = zeros(1,D);           % best population member ever
bestmemit = zeros(1,D);           % best population member in iteration
nfeval    = 0;                    % number of function evaluations
%--------------------------------------------------------------------------

% -----EBC: Initialize population -----------------------------------------------

%rand('seed',sum(100*clock)) ;


if var>=1
   pop = ones(NP,1)*XVmin + rand(NP,D).*(ones(NP,1)*(XVmax - XVmin));
else 
   pop = ones(NP,1)*XVmin + var.*rand(NP,D).*abs(randn(NP,D)).*(ones(NP,1)*(XVmax - XVmin));
   for i=1:NP
    xxx=pop(i,:);
    i_lt_lx=find((xxx<XVmin));
    xxx(i_lt_lx)=XVmin(i_lt_lx);
    i_gt_ux=find((xxx>XVmax));
    xxx(i_gt_ux)=XVmax(i_gt_ux);
    pop(i,:)=xxx;
  end
   
end   
   % Check bounds and enforce them. This is necesary as randn can be >1

  

pop(1,:)=x0;



%--------------------------------------------------------------------------

%------Evaluate the best member after initialization----------------------
ibest   = 1;                      % start with first population member
[val(1) h g] = feval(fname,pop(ibest,:),inputs,results,privstruct);


bestval = val(1);						 % best objective function value so far
nfeval  = nfeval + 1;
for i=2:NP                        % check the remaining members
  [val(i) h g] = feval(fname,pop(i,:),inputs,results,privstruct);
  nfeval  = nfeval + 1;

  
  if (val(i) < bestval)           % if member is better
     ibest   = i;                 % save its location
     bestval = val(i);
 end   
end
bestmemit = pop(ibest,:);         % best member of current iteration
bestvalit = bestval;              % best value of current iteration
bestmem = bestmemit;              % best member ever

%-------------------------------------------------------------------------

%------DE-Minimization---------------------------------------------
%------popold is the population which has to compete. It is--------
%------static through one iteration. pop is the newly--------------
%------emerging population.----------------------------------------

pm1 = zeros(NP,D);              % initialize population matrix 1
pm2 = zeros(NP,D);              % initialize population matrix 2
pm3 = zeros(NP,D);              % initialize population matrix 3
pm4 = zeros(NP,D);              % initialize population matrix 4
pm5 = zeros(NP,D);              % initialize population matrix 5
bm  = zeros(NP,D);              % initialize bestmember  matrix
ui  = zeros(NP,D);              % intermediate population of perturbed vectors
mui = zeros(NP,D);              % mask for intermediate population
mpo = zeros(NP,D);              % mask for old population
rot = (0:1:NP-1);               % rotating index array (size NP)
rotd= (0:1:D-1);                % rotating index array (size D)
rt  = zeros(NP);                % another rotating index array
rtd = zeros(D);                 % rotating index array for exponential crossover
a1  = zeros(NP);                % index array
a2  = zeros(NP);                % index array
a3  = zeros(NP);                % index array
a4  = zeros(NP);                % index array
a5  = zeros(NP);                % index array
ind = zeros(4);

iter = 1;

% --------EBC: open results file----------------------------------------

fid=fopen(inputs.pathd.report,'a+');
fprintf(1,'\n\n-----------------------------------------------------------------------------');
fprintf(1,'\nIter        Best           Mean Cost          Deviation         CPU_time\n');
fprintf(fid,'\nIter         Best            Mean Cost           Deviation         CPU_time\n');
fprintf(1,'-----------------------------------------------------------------------------\n');


%------EBC: Added to change (/add a) convergence criteria------
cvar=1.e10;


while ((iter < itermax) & (cvar > cvarmax)  & (bestval > VTR))

  popold = pop;                   % save the old population
  ind = randperm(4);              % index pointer array
  a1  = randperm(NP);             % shuffle locations of vectors
  rt = rem(rot+ind(1),NP);        % rotate indices by ind(1) positions
  a2  = a1(rt+1);                 % rotate vector locations
  rt = rem(rot+ind(2),NP);
  a3  = a2(rt+1);                
  rt = rem(rot+ind(3),NP);
  a4  = a3(rt+1);               
  rt = rem(rot+ind(4),NP);
  a5  = a4(rt+1);                

  pm1 = popold(a1,:);             % shuffled population 1
  pm2 = popold(a2,:);             % shuffled population 2
  pm3 = popold(a3,:);             % shuffled population 3
  pm4 = popold(a4,:);             % shuffled population 4
  pm5 = popold(a5,:);             % shuffled population 5

  for i=1:NP                      % population filled with the best member
    bm(i,:) = bestmemit;          % of the last iteration
  end  
 mui = rand(NP,D) < CR;          % all random numbers < CR are 1, 0 otherwise
  if (strategy > 5)
    st = strategy-5;		  % binomial crossover
  else
    st = strategy;		  % exponential crossover
    mui=sort(mui');	          % transpose, collect 1's in each column
    for i=1:NP
      n=floor(rand*D);
      if n > 0
         rtd = rem(rotd+n,D);
         mui(:,i) = mui(rtd+1,i); %rotate column i by n
     end
  end

  mui = mui';			  % transpose back

  end
  mpo = mui < 0.5;                % inverse mask to mui

  if (st == 1)                      % DE/best/1
    ui = bm + F*(pm1 - pm2);        % differential variation
    ui = popold.*mpo + ui.*mui;     % crossover
 elseif (st == 2)                  % DE/rand/1
    ui = pm3 + F*(pm1 - pm2);       % differential variation
    ui = popold.*mpo + ui.*mui;     % crossover
 elseif (st == 3)                  % DE/rand-to-best/1
    ui = popold + F*(bm-popold) + F*(pm1 - pm2);        
    ui = popold.*mpo + ui.*mui;     % crossover
 elseif (st == 4)                  % DE/best/2
    ui = bm + F*(pm1 - pm2 + pm3 - pm4);  % differential variation
    ui = popold.*mpo + ui.*mui;           % crossover
 elseif (st == 5)                  % DE/rand/2
    ui = pm5 + F*(pm1 - pm2 + pm3 - pm4);  % differential variation
    ui = popold.*mpo + ui.*mui;            % crossover
 end
%--------------------------------------------------------------------------
 
%-----Select which vectors are allowed to enter the new population------------
% ---- EBC: JRB Check bounds and enforce them-----------

for i=1:NP
    xxx=ui(i,:);
    i_lt_lx=find((xxx<XVmin));
    xxx(i_lt_lx)=XVmin(i_lt_lx)+rand(1)*(XVmax(i_lt_lx) - XVmin(i_lt_lx));
    
    i_gt_ux=find((xxx>XVmax));
     xxx(i_gt_ux)=XVmin(i_gt_ux)+rand(1)*(XVmax(i_gt_ux) - XVmin(i_gt_ux));
    ui(i,:)=xxx;
end
      
%---------------------------------------------------


for i=1:NP
    [tempval temph tempg]= feval(fname,ui(i,:),inputs,results,privstruct);   % check cost of competitor
    nfeval  = nfeval + 1;
    if (tempval <= val(i))  % if competitor is better than value in "cost array"
       pop(i,:) = ui(i,:);  % replace old vector with new one (for new iteration)
       val(i)   = tempval;  % save value in "cost array"
       %----we update bestval only in case of success to save time-----------
       if (tempval < bestval)     % if competitor better than the best one ever      
          bestval = tempval;      % new best value
          bestmem = ui(i,:);      % new best parameter vector ever
       end
    end
 end %---end for imember=1:NP

  bestmemit = bestmem;       % freeze the best member of this iteration for the coming 

                             % iteration. This is needed for some of the strategies.                                                                                

%------------------------------------------------------------------------
% EBC,  Modification to keep information on the mean objective value and
% deviation for each population
cmean=sum(val)/NP;
cvar=(val-cmean)*(val-cmean)';
cvar=cvar/(NP-1); 

if isnan(cvar)
    cvar=1e10;
end
%-----------------------------------------------------------------------
                             
%----EBC: Output section----------------------------------------------------------

  if (refresh > 0)
     cpu_time=cputime - init_time;
       conv_curve(iter,1:2)=[ cpu_time bestval];    
     if (rem(iter,refresh) == 0)
       %fprintf(1,'Iteration: %d,  Best: %f,  F: %f,  CR: %f,  NP: %d\n',iter,bestval,F,CR,NP);   
        fprintf(1,' %d\t\t %d\t\t %d\t\t %d \t\t %f\n',iter,bestval,cmean,cvar,cpu_time);
       fprintf(fid,' %d\t\t %d\t\t %d\t\t %d \t\t %f\n',iter,bestval,cmean,cvar,cpu_time);      
    end   
end

 
 iter = iter + 1;
 

end %---end while ((iter < itermax) ...
   total_cpu_time=cputime - init_time;
   
  
  fprintf(1,'\nBest solution achieved = %d\n\n',bestval);
  fprintf(fid,'\nBest solution achieved = %d\n\n',bestval);
  for n=1:D
    fprintf(1,'thetabest(%d) = %e\n',n,bestmem(n));
    fprintf(fid,'thetabest(%d) = %e\n',n,bestmem(n));
  end
  fprintf(1,'\nTotal CPU time= %f\n\n',total_cpu_time);
  fprintf(fid,'\nTotal CPU time= %f\n\n',total_cpu_time); 

     
   fclose(fid);
%--------------------------------------------------------------------------