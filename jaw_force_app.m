function jaw_force_app(varargin)
%JAW_FORCE_APP  McKibben-muscle jaw: force & torque model for student teams.
%
%   Run it by typing  jaw_force_app  in the Command Window (or press Run).
%   No code editing needed. Works in MATLAB R2020b or newer.
%
%   Tab 1  Jaw setup       enter your team's angles, distances and muscle lengths
%   Tab 2  Measured forces type in load cell readings or import from the leaderboard
%   Tab 3  Jaw simulation  animated jaw with force arrows and a torque graph
%   Tab 4  Results         force/torque graphs, calculated vs. measured table,
%                          and buttons to save PNG graphs and an Excel sheet
%   Tab 5  Force vs. pressure  ideal McKibben equation
%                          F = (pi D0^2 P / 4)(3 cos^2(theta) - 1): muscle and
%                          bite force vs. air pressure, compared with readings
%   Tab 6  Pressure calibration  (Week 9 plan)
%                          Step 1: one muscle pulling straight on the load cell
%                            -> predicted (ideal) vs. measured force -> muscle
%                            correction factor k_M
%                          Step 2: pressure vs. time after pressurizing -> time
%                            constant tau of P(t) = P_end + A e^(-t/tau), and
%                            whether the leak costs real force during a squeeze
%                          Step 3: peak sensor pressure -> predicted muscle force
%                            and jaw (bite) force, compared with Tab 5 readings
%   "Show the math" opens every equation with your numbers plugged in.
%
%   Math used (up to Calc III): vector cross product for torque, single-
%   variable optimization for the best muscle angle, the gradient for where
%   to move the attachment point, partial derivatives for error propagation,
%   vector length for muscle stretch, least squares for the muscle
%   coefficient and the pressure correction factor, and a least-squares
%   exponential fit for the pressure time constant.
%
%   jaw_force_app('selftest') runs the math and saves test graphs without
%   the app window (used to check the file; also works in GNU Octave).

if nargin > 0 && strcmpi(varargin{1}, 'selftest')
    selftest();
    return
end
buildApp();
end

% =========================================================================
%  DATA AND MATH (no user interface; shared by the app and the self-test)
% =========================================================================

function C = appColors()
C.brown   = [87 21 11] / 255;       % Rowan brown
C.gold    = [255 204 0] / 255;      % Rowan gold
C.goldDk  = [176 132 0] / 255;      % darker gold for lines on white
C.ink     = [0.13 0.09 0.08];
C.muted   = [0.40 0.35 0.33];
C.grid    = [0.86 0.84 0.81];
C.skull   = [0.93 0.90 0.85];
C.jaw     = [0.80 0.72 0.62];
C.muscle  = [0.23 0.36 0.16];       % McKibben braid green
C.cell    = [0.55 0.58 0.62];
C.pal = [87 21 11; 201 151 0; 31 122 140; 224 110 31; 106 76 147; 59 125 35; 90 90 90] / 255;
end

function D = exampleData()
D.version  = 1;
D.team     = 'Example team';
D.mode     = 1;          % 1 = sum of both muscles, 2 = average of both muscles
D.a        = -1.6;       % McKibben coefficient [N/mm]
D.sigLen   = 0.5;        % ruler uncertainty on muscle lengths [mm]
D.sigArm   = 1.0;        % uncertainty on moment arms [mm]
D.sigTheta = 2.0;        % uncertainty on muscle angle [deg]
D.L0       = 100;        % typical McKibben muscle length used for the animation [mm]
D.labels   = {'A','B','C','D','E','F','G'};
D.altNames = {'Alt jaw 1','Alt jaw 2','Alt jaw 3'};
%           theta  R_MX  R_MY  R_LC  b1   b2   x1   x2
D.geom = [    5    22    12    95    25   24   15   16
              8    26    12    95    25   24   14   14
             10    34    12    95    25   24   13   14
             30    18    14    95    25   24   17   17
             20    28    16    95    25   24   14   15
             12    31    14    95    25   24   12   13
             18    25    15    95    25   24   15   15 ];
D.meas = NaN(10, 5);
D.meas(1, 1:3)  = [ 9.1  9.6  8.8];
D.meas(2, 1:3)  = [11.2 10.4 11.0];
D.meas(3, 1:3)  = [14.8 15.5 14.1];
D.meas(4, 1:3)  = [ 7.9  8.6  8.1];
D.meas(5, 1:3)  = [12.9 13.8 12.2];
D.meas(6, 1:3)  = [15.9 16.8 16.1];
D.meas(8, 1:3)  = [18.2 19.0 17.5];
D.meas(9, 1:3)  = [12.1 11.8 12.9];
D.meas(10, 1:3) = [21.4 20.6 22.0];
% Pressure model (Tab 5)
D.D0       = 12;         % McKibben actuator diameter, relaxed [mm]
D.braid0   = 25;         % braid angle of the relaxed muscle, from its long axis [deg]
D.Lm       = 100;        % relaxed muscle length used for the contraction ratio [mm]
D.Pmax     = 250;        % highest pressure on the graph [kPa]
D.pressOri = 6;          % orientation the pressure readings were taken in
D.press    = NaN(8, 2);  % columns: gauge pressure [kPa], load cell force [N]
% Pressure calibration (Tab 6). Pressures here are in D.calUnit (psi or kPa).
D.calUnit  = 'psi';      % units of the pressure sensor readings on Tab 6
D.calX     = 0;          % how much the muscle shortens during the calibration pull [mm]
D.cal      = NaN(8, 2);  % columns: peak pressure [calUnit], measured muscle force [N]
D.cal(1:5, :) = [ 5  3.5; 10  6.8; 15 10.4; 20 13.6; 25 17.2];   % example numbers
D.decay    = NaN(12, 2); % columns: time [s], pressure [calUnit]
D.decay(1:11, :) = [ 0 20.0; 1.5 19.5; 3 19.0; 4.5 18.6; 6 18.1; 7.5 17.6; ...
                     9 17.2; 10.5 16.8; 12 16.4; 13.5 15.9; 15 15.6];   % example numbers
D.decayMode = 1;         % 1 = leaks down toward 0 gauge, 2 = settles at a fitted end value
D.tHold    = 2;          % how long one squeeze lasts [s]
D.peakP    = 15;         % peak sensor pressure used for the prediction [calUnit]
D.calIsExample = true;   % Tab 6 tables still hold the example numbers
D.isExample = true;
end

function D = fillDefaults(D)
% Older team files don't have the newer fields; add the defaults (empty tables).
E = exampleData();
E.cal(:) = NaN;  E.decay(:) = NaN;  E.calIsExample = false;
f = {'D0', 'braid0', 'Lm', 'Pmax', 'pressOri', 'press', ...
     'calUnit', 'calX', 'cal', 'decay', 'decayMode', 'tHold', 'peakP', 'calIsExample'};
for k = 1:numel(f)
    if ~isfield(D, f{k}), D.(f{k}) = E.(f{k}); end
end
end

function F = mckibbenForce(P_kPa, D0_mm, thetaDeg)
% Ideal McKibben (Gaylord) equation:  F = (pi D0^2 P / 4)(3 cos^2(theta) - 1)
% P in kPa, D0 in mm, theta (braid angle from the muscle axis) in deg -> F in N.
F = (pi * (D0_mm*1e-3).^2 / 4) .* (P_kPa*1e3) .* (3*cosd(thetaDeg).^2 - 1);
F = max(F, 0);           % a muscle can only pull
end

function Pk = syringePressure(V0, V)
% Boyle's law for a sealed syringe + tubing + muscle: gauge pressure [kPa].
Pk = 101.325 * (V0 ./ V - 1);
end

function P = pressureModel(D, M, i)
% Force-vs-pressure relationship for orientation i.
g = D.geom(i,:);  c = muscleFactor(D);
P.valid = M.valid(i) && D.D0 > 0 && D.Lm > 0 && D.braid0 > 0 && D.braid0 < 90;
% Each muscle shortens by x, so its braid angle at the load cell grows:
%   cos(theta) = (1 - eps) cos(theta0),  eps = x / L
P.eps   = [g(7) g(8)] / D.Lm;
cth     = min(max((1 - P.eps) * cosd(D.braid0), 0), 1);
P.theta = acosd(cth);
P.perMuscle = mckibbenForce(1, D.D0, P.theta);     % N of force per kPa, each muscle
P.slopeM  = c * sum(P.perMuscle);                  % N per kPa, muscle force in the moment balance
P.arm = M.arm(i);  P.RLC = g(4);
P.slopeLC = P.slopeM * P.arm / P.RLC;              % N of bite force per kPa
P.FM  = M.FM(i);  P.FLC = M.F(i);
if P.slopeM > 0, P.Pimp = P.FM / P.slopeM; else, P.Pimp = NaN; end
% Ideal free contraction: force reaches zero when theta = 54.7 deg
P.epsMax  = max(0, 1 - 1/(sqrt(3)*cosd(D.braid0)));
P.bTheory = P.epsMax * D.Lm;
P.b = [g(5) g(6)];
% Measured pressure readings
ok = all(isfinite(D.press), 2);
P.Pm = D.press(ok, 1);  P.Fm = D.press(ok, 2);
P.k = NaN;  P.fit = [NaN NaN];  P.R2 = NaN;
Ft = P.slopeLC * P.Pm;
if ~isempty(P.Pm) && sum(Ft.^2) > 0
    P.k = sum(P.Fm .* Ft) / sum(Ft.^2);           % measured = k x ideal theory
end
if numel(P.Pm) >= 2 && max(P.Pm) > min(P.Pm)
    P.fit = polyfit(P.Pm, P.Fm, 1);                % F = m P + c0
    ssRes = sum((P.Fm - polyval(P.fit, P.Pm)).^2);  ssTot = sum((P.Fm - mean(P.Fm)).^2);
    if ssTot > 0, P.R2 = 1 - ssRes/ssTot; end
end
% Muscle correction factor from the Tab 6 calibration, and what is left for the jaw
Q = calModel(D);
P.kM = Q.kM;
P.kJ = NaN;  P.errCorr = NaN;
if isfinite(P.kM) && P.kM > 0
    if isfinite(P.k), P.kJ = P.k / P.kM; end       % measured = k_M x k_J x ideal theory
    Fc = P.kM * P.slopeLC * P.Pm;                  % bite force predicted with corrected muscle
    okc = Fc > 0;
    if any(okc), P.errCorr = mean(abs(P.Fm(okc) - Fc(okc)) ./ Fc(okc)) * 100; end
end
end

function k = kPaPer(unit)
% kPa in one unit of the Tab 6 pressure readings
if strcmpi(unit, 'psi'), k = 6.894757; else, k = 1; end
end

function Q = calModel(D)
% Step 1 of the Week 9 plan: one McKibben muscle pulling straight on the load cell.
%   predicted XX = ideal McKibben force at the measured peak pressure
%   measured  YY = load cell reading
%   correction factor k_M = least squares fit of YY = k_M * XX (through zero)
u = kPaPer(D.calUnit);
Q.unit = D.calUnit;  Q.u = u;
Q.valid = D.D0 > 0 && D.Lm > 0 && D.braid0 > 0 && D.braid0 < 90 && ...
          isfinite(D.calX) && D.calX >= 0 && D.calX < D.Lm;
cth = min(max((1 - D.calX / D.Lm) * cosd(D.braid0), 0), 1);
Q.theta   = acosd(cth);                             % braid angle during the calibration pull
Q.perKPa  = mckibbenForce(1, D.D0, Q.theta);        % ideal N per kPa, one muscle
Q.perUnit = Q.perKPa * u;                           % ideal N per psi (or per kPa)
ok = all(isfinite(D.cal), 2) & D.cal(:,1) >= 0;
Q.P  = D.cal(ok, 1);  Q.Fm = D.cal(ok, 2);
Q.Fi = Q.perUnit * Q.P;                             % predicted (ideal) force XX
Q.n  = numel(Q.P);
Q.kM = NaN;  Q.R2 = NaN;  Q.fit = [NaN NaN];  Q.fitR2 = NaN;
if Q.valid && Q.n >= 1 && sum(Q.Fi.^2) > 0
    Q.kM = sum(Q.Fm .* Q.Fi) / sum(Q.Fi.^2);
    ssTot = sum((Q.Fm - mean(Q.Fm)).^2);
    if Q.n >= 2 && ssTot > 0, Q.R2 = 1 - sum((Q.Fm - Q.kM*Q.Fi).^2) / ssTot; end
end
if Q.n >= 2 && max(Q.P) > min(Q.P)
    Q.fit = polyfit(Q.P, Q.Fm, 1);                  % F = m P + c0, P in Q.unit
    ssTot = sum((Q.Fm - mean(Q.Fm)).^2);
    if ssTot > 0, Q.fitR2 = 1 - sum((Q.Fm - polyval(Q.fit, Q.P)).^2) / ssTot; end
end
end

function [sse, A, Pend] = expSSE(tau, s, p, mode)
% Best A (and end value) for a given tau; returns the sum of squared errors.
e = exp(-s / tau);
if mode == 1
    A = sum(e .* p) / sum(e.^2);  Pend = 0;
else
    c = [ones(size(e)) e] \ p;  Pend = c(1);  A = c(2);
end
sse = sum((p - Pend - A*e).^2);
end

function T = decayModel(D)
% Step 2 of the Week 9 plan: time constant of the pressure after pressurizing.
%   P(t) = P_end + A e^(-(t - t0)/tau)      (P_end = 0 for a leak to air)
% tau is found by least squares: for each trial tau the best A (and P_end) is a
% straight-line fit, so we search over tau and keep the smallest error.
ok = all(isfinite(D.decay), 2);
t = D.decay(ok, 1);  p = D.decay(ok, 2);
[t, o] = sort(t);  p = p(o);
T.t = t;  T.p = p;  T.n = numel(t);  T.mode = D.decayMode;  T.unit = D.calUnit;
T.tHold = D.tHold;  T.tau = NaN;  T.A = NaN;  T.Pend = NaN;  T.R2 = NaN;  T.t0 = NaN;
T.half = NaN;  T.t5 = NaN;  T.loss = NaN;  T.atEdge = false;  T.rising = false;
need = 3;  if T.mode == 2, need = 4; end
if T.n < need || max(t) <= min(t), return, end
T.t0 = t(1);  s = t - T.t0;  span = max(s);
lg = linspace(log10(span/1000), log10(span*1000), 600);
sse = zeros(size(lg));
for j = 1:numel(lg), sse(j) = expSSE(10^lg(j), s, p, T.mode); end
[sBest, j] = min(sse);
T.atEdge = (j == 1 || j == numel(lg));
lt = lg(j);
if ~T.atEdge
    obj = @(x) expSSE(10^x, s, p, T.mode);
    x = fminbnd(obj, lg(j-1), lg(j+1));
    if obj(x) <= sBest, lt = x; end
end
T.tau = 10^lt;
[sseFit, T.A, T.Pend] = expSSE(T.tau, s, p, T.mode);
ssTot = sum((p - mean(p)).^2);
if ssTot > 0, T.R2 = 1 - sseFit / ssTot; end
T.rising = T.A < 0;                                 % pressure climbing = a fill curve
T.half = T.tau * log(2);
T.t5   = -T.tau * log(0.95);                        % time to lose 5% of the change
P0 = T.Pend + T.A;                                  % fitted pressure at the first reading
if P0 > 0
    T.loss = T.A * (1 - exp(-T.tHold / T.tau)) / P0;   % fraction of peak force lost in one squeeze
end
end

function T = decayCurve(T, tv)
% Fitted pressure at times tv (same units as the readings).
T.curve = T.Pend + T.A * exp(-(tv - T.t0) / T.tau);
end

function R = peakPredict(D, M, i)
% Step 3 of the Week 9 plan: peak sensor pressure -> muscle force -> jaw force.
P = pressureModel(D, M, i);
R.P = P;  R.unit = D.calUnit;  R.Pin = D.peakP;
R.Pk = D.peakP * kPaPer(D.calUnit);
R.valid = P.valid && isfinite(R.Pk) && R.Pk >= 0;
R.FMideal  = P.slopeM  * R.Pk;                     % ideal muscle force in the moment balance
R.FLCideal = P.slopeLC * R.Pk;                     % ideal bite force
R.kM = P.kM;
R.FMcorr  = R.kM * R.FMideal;                      % NaN until Step 1 has readings
R.FLCcorr = R.kM * R.FLCideal;
R.FLCjaw  = NaN;
if isfinite(P.k), R.FLCjaw = P.k * R.FLCideal; end % using the jaw readings from Tab 5
end

function c = muscleFactor(D)
if D.mode == 2, c = 0.5; else, c = 1; end
end

function names = rowNames(D)
names = [D.labels, D.altNames];
end

function M = computeModel(D)
% Everything the app reports, computed from the data struct D.
g = D.geom;  a = D.a;  c = muscleFactor(D);
th = g(:,1) * pi/180;  RMX = g(:,2);  RMY = g(:,3);  RLC = g(:,4);
b1 = g(:,5);  b2 = g(:,6);  x1 = g(:,7);  x2 = g(:,8);

M.valid = all(isfinite(g), 2) & RLC > 0;
M.FM1 = a * (x1 - b1);
M.FM2 = a * (x2 - b2);
M.FM  = c * (M.FM1 + M.FM2);
M.arm = RMX .* cos(th) + RMY .* sin(th);          % effective moment arm [mm]
M.tau = M.FM .* M.arm;                            % muscle torque [N*mm]
M.F   = M.tau ./ RLC;                             % predicted load cell force [N]
M.F(~M.valid) = NaN;

% Partial derivatives of F_LC with respect to each measured quantity
M.qNames = {'theta', 'R_MX', 'R_MY', 'R_LC', 'b1', 'b2', 'x1', 'x2'};
dx = c * a * M.arm ./ RLC;
M.dF = [ M.FM .* (RMY.*cos(th) - RMX.*sin(th)) ./ RLC, ...   % dF/dtheta (per radian)
         M.FM .* cos(th) ./ RLC, ...                          % dF/dR_MX
         M.FM .* sin(th) ./ RLC, ...                          % dF/dR_MY
        -M.F ./ RLC, ...                                      % dF/dR_LC
        -dx, -dx, dx, dx ];                                   % dF/db1, db2, dx1, dx2
M.sigQ = [D.sigTheta*pi/180, D.sigArm, D.sigArm, D.sigArm, D.sigLen, D.sigLen, D.sigLen, D.sigLen];
M.contrib = (M.dF .* repmat(M.sigQ, 7, 1)).^2;
M.sigF = sqrt(sum(M.contrib, 2));
tot = sum(M.contrib, 2);  tot(tot == 0) = 1;
M.groupFrac = [sum(M.contrib(:,5:8),2), sum(M.contrib(:,2:4),2), M.contrib(:,1)] ./ repmat(tot, 1, 3);
M.groupNames = {'Muscle lengths (x, b)', 'Moment arms (R)', 'Muscle angle (\theta)'};

% Optimization and gradient
M.thetaBest = atan2(RMY, RMX) * 180/pi;
M.Fbest = M.FM .* hypot(RMX, RMY) ./ RLC;
M.grad  = [M.FM .* cos(th) ./ RLC, M.FM .* sin(th) ./ RLC];

% Measured statistics (rows 1-7 orientations, 8-10 alternate jaws)
M.measMean = NaN(10,1);  M.measSD = NaN(10,1);  M.measN = zeros(10,1);
for r = 1:10
    v = D.meas(r, isfinite(D.meas(r,:)));
    M.measN(r) = numel(v);
    if ~isempty(v), M.measMean(r) = mean(v); end
    if numel(v) > 1, M.measSD(r) = std(v); elseif numel(v) == 1, M.measSD(r) = 0; end
end
M.pctErr = abs(M.measMean(1:7) - M.F) ./ M.F * 100;
M.pctErr(~(M.measN(1:7) > 0) | ~(M.F > 0)) = NaN;
M.within = abs(M.measMean(1:7) - M.F) <= 2 * M.sigF;

% Least squares: F = k*u with u = c*sum(b - x)*arm/R_LC, and a_fit = -k
u = c * ((b1 - x1) + (b2 - x2)) .* M.arm ./ RLC;
U = [];  Fm = [];
for r = 1:7
    if M.valid(r) && isfinite(u(r))
        v = D.meas(r, isfinite(D.meas(r,:)));
        U = [U; repmat(u(r), numel(v), 1)];  Fm = [Fm; v(:)];
    end
end
M.u = u;  M.fitU = U;  M.fitF = Fm;
if numel(U) >= 2 && sum(U.^2) > 0
    M.k = sum(U .* Fm) / sum(U.^2);
    M.aFit = -M.k;
    ssRes = sum((Fm - M.k*U).^2);  ssTot = sum((Fm - mean(Fm)).^2);
    if ssTot > 0, M.R2 = 1 - ssRes/ssTot; else, M.R2 = NaN; end
else
    M.k = NaN;  M.aFit = NaN;  M.R2 = NaN;
end
end

function K = jawKin(D, i, phiDeg)
% Jaw position and forces when the jaw is opened by phiDeg (0 = on the load cell).
g = D.geom(i,:);  c = muscleFactor(D);
th = g(1)*pi/180;  RMX = g(2);  RMY = g(3);  RLC = g(4);
b1 = g(5);  b2 = g(6);  x1 = g(7);  x2 = g(8);
phi = phiDeg * pi/180;
R = [cos(phi) sin(phi); -sin(phi) cos(phi)];     % clockwise rotation = opening
P0 = [RMX; RMY];
K.S = P0 + D.L0 * [-sin(th); cos(th)];           % muscle anchor on the skull (fixed)
K.P = R * P0;                                     % muscle attachment on the jaw
K.T = R * [RLC; 0];                               % bite point on the load cell
d = K.S - K.P;
K.L  = norm(d);
K.dL = K.L - D.L0;                                % stretch compared with the closed jaw
F1 = max(0, D.a * ((x1 - K.dL) - b1));
F2 = max(0, D.a * ((x2 - K.dL) - b2));
K.FM = c * (F1 + F2);
K.uhat = d / K.L;
K.Fvec = K.FM * K.uhat;
K.tau  = K.P(1)*K.Fvec(2) - K.P(2)*K.Fvec(1);    % z-component of r x F
K.Fbite = K.tau / (RLC * cos(phi));
K.R = R;
end

function lines = mathText(D, M, i)
% Step-by-step math for orientation i, with the team's numbers plugged in.
nm = rowNames(D);
L = {};
if i > 7
    L{end+1} = sprintf('%s is an alternate jaw: measured only, no calculation.', nm{i});
    if M.measN(i) > 0
        L{end+1} = sprintf('Measured: %.2f N average, SD %.2f N, from %d squeezes.', M.measMean(i), M.measSD(i), M.measN(i));
    end
    lines = L;  return
end
g = D.geom(i,:);  c = muscleFactor(D);  a = D.a;
th = g(1);  RMX = g(2);  RMY = g(3);  RLC = g(4);
if ~M.valid(i)
    lines = {sprintf('Orientation %s is missing numbers on the Jaw setup tab.', nm{i})};  return
end
modeTxt = 'F_M = F_M1 + F_M2          (both muscles pull)';
if c == 0.5, modeTxt = 'F_M = (F_M1 + F_M2) / 2    (average of both muscles)'; end
Fv = M.FM(i) * [-sind(th), cosd(th)];

L{end+1} = sprintf('ORIENTATION %s  (%s)', nm{i}, D.team);
L{end+1} = repmat('=', 1, 64);
L{end+1} = '';
L{end+1} = '1. MUSCLE FORCE (linear McKibben model)';
L{end+1} = sprintf('   F_M1 = a(x1 - b1) = %.2f x (%.1f - %.1f) = %.2f N', a, g(7), g(5), M.FM1(i));
L{end+1} = sprintf('   F_M2 = a(x2 - b2) = %.2f x (%.1f - %.1f) = %.2f N', a, g(8), g(6), M.FM2(i));
L{end+1} = ['   ' modeTxt];
L{end+1} = sprintf('   F_M = %.2f N', M.FM(i));
L{end+1} = '';
L{end+1} = '2. TORQUE AS A CROSS PRODUCT  (Calc III: vectors)';
L{end+1} = '   Position of the muscle attachment, measured from the pivot A:';
L{end+1} = sprintf('     r = <R_MX, R_MY, 0> = <%.1f, %.1f, 0> mm', RMX, RMY);
L{end+1} = sprintf('   Muscle force, pulling along the muscle at theta = %.1f deg from vertical:', th);
L{end+1} = sprintf('     F = F_M <-sin(theta), cos(theta), 0> = <%.2f, %.2f, 0> N', Fv(1), Fv(2));
L{end+1} = '   Torque about the pivot:';
L{end+1} = '     tau = r x F = det | i    j    k |';
L{end+1} = '                       | r_x  r_y  0 |';
L{end+1} = '                       | F_x  F_y  0 |  = (r_x F_y - r_y F_x) k';
L{end+1} = sprintf('     tau = (%.1f)(%.2f) - (%.1f)(%.2f) = %.1f N*mm', RMX, Fv(2), RMY, Fv(1), M.tau(i));
L{end+1} = '   Expanding gives F_M (R_MX cos(theta) + R_MY sin(theta)), which is';
L{end+1} = '   exactly the muscle term in the class moment equation.';
L{end+1} = '';
L{end+1} = '3. MOMENT BALANCE -> PREDICTED LOAD CELL FORCE';
L{end+1} = '   Sum M_A = -F_M sin(theta) R_MY - F_M cos(theta) R_MX + F_LC R_LC = 0';
L{end+1} = sprintf('   F_LC = tau / R_LC = %.1f / %.1f = %.2f N', M.tau(i), RLC, M.F(i));
L{end+1} = '';
L{end+1} = '4. BEST MUSCLE ANGLE  (Calc I: optimization)';
L{end+1} = '   F_LC(theta) = (F_M / R_LC)(R_MX cos(theta) + R_MY sin(theta))';
L{end+1} = '   dF_LC/dtheta = (F_M / R_LC)(-R_MX sin(theta) + R_MY cos(theta)) = 0';
L{end+1} = sprintf('   => tan(theta*) = R_MY / R_MX = %.1f / %.1f   =>   theta* = %.1f deg', RMY, RMX, M.thetaBest(i));
L{end+1} = '   The second derivative is negative there, so it is a maximum:';
L{end+1} = sprintf('   F_LC(theta*) = (F_M / R_LC) sqrt(R_MX^2 + R_MY^2) = %.2f N  (%+.1f%% vs. your angle)', ...
                   M.Fbest(i), (M.Fbest(i)/M.F(i) - 1)*100);
L{end+1} = '';
L{end+1} = '5. WHERE TO MOVE THE ATTACHMENT POINT  (Calc III: gradient)';
L{end+1} = '   grad F_LC = < dF/dR_MX, dF/dR_MY > = (F_M / R_LC) < cos(theta), sin(theta) >';
L{end+1} = sprintf('             = < %.3f, %.3f > N per mm', M.grad(i,1), M.grad(i,2));
L{end+1} = sprintf('   Moving the attachment 1 mm in the gradient direction adds about %.3f N.', norm(M.grad(i,:)));
L{end+1} = '   The gradient is perpendicular to the muscle''s line of pull, so the best move';
L{end+1} = '   is one that lengthens the lever arm (usually farther from the pivot).';
L{end+1} = '';
L{end+1} = '6. UNCERTAINTY FROM PARTIAL DERIVATIVES  (Calc III: error propagation)';
L{end+1} = '   sigma_F = sqrt( sum over q of (dF/dq * sigma_q)^2 )';
L{end+1} = sprintf('   %-7s %14s %12s %14s %8s', 'q', 'dF/dq', 'sigma_q', '(dF/dq*s)^2', 'share');
units = {'N/rad','N/mm','N/mm','N/mm','N/mm','N/mm','N/mm','N/mm'};
sq = {sprintf('%.3f rad', M.sigQ(1)), sprintf('%.1f mm', M.sigQ(2)), sprintf('%.1f mm', M.sigQ(3)), ...
      sprintf('%.1f mm', M.sigQ(4)), sprintf('%.1f mm', M.sigQ(5)), sprintf('%.1f mm', M.sigQ(6)), ...
      sprintf('%.1f mm', M.sigQ(7)), sprintf('%.1f mm', M.sigQ(8))};
tot = sum(M.contrib(i,:));
for q = 1:8
    L{end+1} = sprintf('   %-7s %8.3f %-5s %12s %14.4f %7.1f%%', M.qNames{q}, M.dF(i,q), units{q}, sq{q}, ...
                       M.contrib(i,q), 100*M.contrib(i,q)/max(tot, eps));
end
[~, big] = max(M.contrib(i,:));
L{end+1} = sprintf('   sigma_F = %.2f N   =>   F_LC = %.2f +/- %.2f N  (about 95%%: +/- %.2f N)', ...
                   M.sigF(i), M.F(i), M.sigF(i), 2*M.sigF(i));
L{end+1} = sprintf('   Biggest source of uncertainty: %s. Measure it most carefully.', M.qNames{big});
L{end+1} = '';
L{end+1} = '7. COMPARE WITH THE LOAD CELL';
if M.measN(i) > 0
    L{end+1} = sprintf('   Measured: %.2f N average (SD %.2f N, %d squeezes)', M.measMean(i), M.measSD(i), M.measN(i));
    L{end+1} = sprintf('   %% error = |measured - calculated| / calculated x 100 = %.1f%%', M.pctErr(i));
    if M.within(i)
        L{end+1} = '   The measurement is within 2 sigma_F of the prediction: consistent with the model.';
    else
        L{end+1} = '   The measurement is outside 2 sigma_F: something the model ignores matters here';
        L{end+1} = '   (friction, muscle stretch, bending, the linear muscle model...).';
    end
else
    L{end+1} = '   No measured squeezes for this orientation yet.';
end
L{end+1} = '';
L{end+1} = '8. MUSCLE LENGTH AS THE JAW OPENS  (vector length)';
L{end+1} = '   The skull anchor S stays fixed. The jaw attachment rotates: P(phi) = R(phi) r.';
L{end+1} = '   Muscle length  L(phi) = || S - P(phi) ||';
L{end+1} = '   Opening stretches the muscle, so it shortens less: x(phi) = x - (L(phi) - L0),';
L{end+1} = sprintf('   and its force rises. (The animation assumes a typical L0 = %.0f mm.)', D.L0);
L{end+1} = '';
L{end+1} = '9. YOUR MUSCLE COEFFICIENT FROM LEAST SQUARES  (all orientations)';
L{end+1} = '   Model: F = k u,  u = c (b1 - x1 + b2 - x2)(R_MX cos(theta) + R_MY sin(theta)) / R_LC';
L{end+1} = '   Minimize  S(k) = sum (F_i - k u_i)^2';
L{end+1} = '   dS/dk = -2 sum u_i (F_i - k u_i) = 0   =>   k = sum(u_i F_i) / sum(u_i^2)';
if isfinite(M.k)
    L{end+1} = sprintf('   k = %.3f N/mm  =>  a_fit = -k = %.2f N/mm   (class value a = %.2f)', M.k, M.aFit, D.a);
    L{end+1} = sprintf('   R^2 = %.3f from %d squeezes.', M.R2, numel(M.fitU));
else
    L{end+1} = '   Needs measured squeezes for at least one orientation.';
end
L{end+1} = '';
P = pressureModel(D, M, i);
L{end+1} = '10. FORCE FROM AIR PRESSURE  (ideal McKibben equation)';
L{end+1} = '   F = (pi D0^2 P / 4)(3 cos^2(theta) - 1)';
L{end+1} = '   Braid angle at the load cell, from the relaxed angle and the contraction:';
L{end+1} = '     cos(theta) = (1 - x/L) cos(theta0)';
L{end+1} = sprintf('     muscle 1: (1 - %.1f/%.0f) cos(%.1f) -> theta = %.1f deg', D.geom(i,7), D.Lm, D.braid0, P.theta(1));
L{end+1} = sprintf('     muscle 2: (1 - %.1f/%.0f) cos(%.1f) -> theta = %.1f deg', D.geom(i,8), D.Lm, D.braid0, P.theta(2));
L{end+1} = sprintf('   Force per kPa = (pi D0^2 / 4)(1000)(3 cos^2(theta) - 1), D0 = %.1f mm:', D.D0);
L{end+1} = sprintf('     muscle 1: %.4f N/kPa     muscle 2: %.4f N/kPa', P.perMuscle(1), P.perMuscle(2));
L{end+1} = sprintf('   Muscle force in the moment balance: F_M = %.4f N/kPa x P', P.slopeM);
L{end+1} = sprintf('   Bite force: F_LC = F_M x arm / R_LC = %.4f x %.1f / %.1f = %.4f N/kPa x P', ...
                   P.slopeM, P.arm, P.RLC, P.slopeLC);
L{end+1} = '   Force is LINEAR in pressure: doubling the pressure doubles the force.';
if isfinite(P.Pimp)
    L{end+1} = sprintf('   The class model gives F_M = %.2f N. An ideal muscle needs P = %.2f / %.4f = %.0f kPa', ...
                       P.FM, P.FM, P.slopeM, P.Pimp);
    L{end+1} = sprintf('   (%.1f psi) to make that force.', P.Pimp / 6.895);
end
L{end+1} = '   Free contraction (no load) ends when 3 cos^2(theta) = 1, theta = 54.7 deg:';
L{end+1} = sprintf('     eps_max = 1 - 1/(sqrt(3) cos(theta0)) = %.3f  ->  b_ideal = %.1f mm', P.epsMax, P.bTheory);
L{end+1} = sprintf('     your measured b1, b2 = %.1f, %.1f mm (the rubber bladder makes the real value smaller)', P.b(1), P.b(2));
if i == D.pressOri && isfinite(P.k)
    L{end+1} = sprintf('   Your pressure readings: measured = %.0f%% of ideal theory (k = %.2f).', 100*P.k, P.k);
    if isfinite(P.R2)
        L{end+1} = sprintf('   Linear fit: F_LC = %.4f P + %.2f   (R^2 = %.3f)', P.fit(1), P.fit(2), P.R2);
    end
end
L = [L, calMathText(D, M, i)];
lines = L;
end

function L = calMathText(D, M, i)
% Sections 11-13: the Week 9 pressure calibration (Tab 6).
Q = calModel(D);  T = decayModel(D);  R = peakPredict(D, M, i);
un = D.calUnit;  nm = rowNames(D);
L = {''};
L{end+1} = '11. MUSCLE CALIBRATION: PRESSURE -> FORCE  (one muscle straight on the load cell)';
L{end+1} = '   Braid angle during the pull: cos(theta) = (1 - x_cal/L) cos(theta0)';
L{end+1} = sprintf('     (1 - %.1f/%.0f) cos(%.1f) -> theta = %.1f deg', D.calX, D.Lm, D.braid0, Q.theta);
L{end+1} = sprintf('   Predicted (ideal) force per %s: (pi D0^2/4)(%.3f kPa/%s)(1000)(3 cos^2(theta) - 1) = %.4f N/%s', ...
                   un, Q.u, un, Q.perUnit, un);
if Q.n > 0
    L{end+1} = sprintf('   %12s %16s %14s %10s', ['P (' un ')'], 'Predicted XX (N)', 'Measured YY', 'YY/XX');
    for r = 1:Q.n
        rat = NaN;  if Q.Fi(r) > 0, rat = Q.Fm(r) / Q.Fi(r); end
        L{end+1} = sprintf('   %12.2f %16.2f %14.2f %10.2f', Q.P(r), Q.Fi(r), Q.Fm(r), rat); %#ok<AGROW>
    end
    L{end+1} = '   Correction factor (least squares through zero):';
    L{end+1} = '     minimize sum (YY - k_M XX)^2  =>  k_M = sum(XX YY) / sum(XX^2)';
    if isfinite(Q.kM)
        L{end+1} = sprintf('     k_M = %.3f   (the real muscle makes %.0f%% of the ideal force; R^2 = %.3f)', ...
                           Q.kM, 100*Q.kM, Q.R2);
        L{end+1} = sprintf('   Corrected muscle model: F = %.3f x %.4f N/%s x P = %.4f N/%s x P', ...
                           Q.kM, Q.perUnit, un, Q.kM*Q.perUnit, un);
    end
    if isfinite(Q.fitR2)
        L{end+1} = sprintf('   Straight-line check: F = %.4f P %+.2f N  (R^2 = %.3f). A big intercept means', ...
                           Q.fit(1), Q.fit(2), Q.fitR2);
        L{end+1} = '   the bladder needs some pressure before it pulls (a dead band the ideal model ignores).';
    end
else
    L{end+1} = '   Enter peak pressure and load cell force for one muscle on Tab 6, Step 1.';
end
L{end+1} = '';
L{end+1} = sprintf('12. PEAK PRESSURE -> JAW FORCE  (orientation %s, peak P = %.2f %s = %.1f kPa)', ...
                   nm{i}, R.Pin, un, R.Pk);
if R.valid
    L{end+1} = sprintf('   Ideal muscle force   F_M  = %.4f N/kPa x %.1f kPa = %.2f N', R.P.slopeM, R.Pk, R.FMideal);
    L{end+1} = sprintf('   Ideal bite force     F_LC = F_M x arm / R_LC = %.2f x %.1f / %.1f = %.2f N', ...
                       R.FMideal, R.P.arm, R.P.RLC, R.FLCideal);
    if isfinite(R.kM)
        L{end+1} = sprintf('   With k_M = %.3f:     F_M = %.2f N,  F_LC = %.2f N   <- prediction to test', ...
                           R.kM, R.FMcorr, R.FLCcorr);
    end
    if isfinite(R.P.kJ)
        L{end+1} = sprintf('   Tab 5 jaw readings: measured = %.2f x ideal = k_M x k_J,  so the jaw factor k_J = %.3f', ...
                           R.P.k, R.P.kJ);
        L{end+1} = '   (k_J < 1: losses in the jaw itself, such as friction, misalignment or bending.)';
        L{end+1} = sprintf('   Corrected prediction vs. jaw readings: %.1f%% average error.', R.P.errCorr);
    end
else
    L{end+1} = '   Fill in this orientation and the muscle settings first.';
end
L{end+1} = '';
L{end+1} = '13. PRESSURE TIME CONSTANT  (leak or fill curve)';
L{end+1} = '   Model: P(t) = P_end + A e^(-(t - t0)/tau)';
if T.mode == 1, L{end+1} = '   Leak-down: P_end = 0 gauge (air escapes until the muscle is empty).'; end
L{end+1} = '   For each trial tau the best A (and P_end) is a straight-line fit; keep the tau with the';
L{end+1} = '   smallest sum of squared errors (one-variable minimization over tau).';
if isfinite(T.tau)
    L{end+1} = sprintf('   tau = %.2f s,  A = %.2f %s,  P_end = %.2f %s,  R^2 = %.4f  (%d readings)', ...
                       T.tau, T.A, un, T.Pend, un, T.R2, T.n);
    if T.atEdge
        L{end+1} = '   tau hit the edge of the search: the readings barely change, so the leak is too slow';
        L{end+1} = '   to measure over this time window. Record for longer if you need a number.';
    end
    L{end+1} = sprintf('   After 1 tau the change is 63%% done; after 5 tau (%.1f s) it is 99%% done.', 5*T.tau);
    if T.rising
        L{end+1} = '   Pressure is rising: this is a fill curve. A smaller tau means a faster fill';
        L{end+1} = '   (a bigger connector hole or shorter tubing lowers tau).';
    else
        L{end+1} = sprintf('   Half-life = tau ln 2 = %.2f s.  Time to lose 5%% = -tau ln(0.95) = %.2f s.', T.half, T.t5);
        if isfinite(T.loss)
            L{end+1} = '   Force is linear in pressure, so the share of peak force lost in one squeeze is';
            L{end+1} = sprintf('     A (1 - e^(-t_hold/tau)) / P(t0) = %.1f%%  for a %.1f s squeeze.', 100*T.loss, T.tHold);
            if T.loss < 0.05
                L{end+1} = '   Under 5%: the leak does not change the peak load. No fix needed.';
            else
                L{end+1} = '   5% or more: the leak lowers the peak load. Seal near the sensor or read the peak sooner.';
            end
        end
    end
else
    need = 3;  if T.mode == 2, need = 4; end
    L{end+1} = sprintf('   Enter at least %d (time, pressure) readings on Tab 6, Step 2.', need);
end
end

function C = resultsCell(D, M)
% Results table as a cell array (used for the app table and the Excel file).
nm = rowNames(D);
C = cell(10, 11);
for r = 1:10
    C{r,1} = nm{r};
    if r <= 7 && M.valid(r)
        C{r,2} = D.geom(r,1);  C{r,3} = rnd(M.FM(r),2);  C{r,4} = rnd(M.tau(r),1);
        C{r,5} = rnd(M.F(r),2);  C{r,6} = rnd(M.sigF(r),2);  C{r,11} = rnd(M.thetaBest(r),1);
    end
    if M.measN(r) > 0
        C{r,7} = rnd(M.measMean(r),2);  C{r,8} = rnd(M.measSD(r),2);  C{r,9} = M.measN(r);
    end
    if r <= 7 && isfinite(M.pctErr(r)), C{r,10} = rnd(M.pctErr(r),1); end
end
end

function y = rnd(x, n)
y = round(x * 10^n) / 10^n;
end

function h = resultsHeader()
h = {'Orientation', 'Angle theta (deg)', 'Muscle force F_M (N)', 'Torque tau (N*mm)', ...
     'Calculated F_LC (N)', '+/- uncertainty (N)', 'Measured mean (N)', 'SD (N)', 'n', ...
     '% error', 'Best angle (deg)'};
end

% =========================================================================
%  DRAWING (used by the app and the self-test)
% =========================================================================

function names = graphNames()
names = {'Calculated vs. measured force', 'Parity plot (measured vs. calculated)', ...
         'Force vs. muscle angle (best angle)', 'Torque as the jaw opens', ...
         'Which measurement matters most', 'Least-squares muscle coefficient'};
end

function styleAxes(ax, C)
set(ax, 'Color', 'w', 'XColor', C.ink, 'YColor', C.ink, 'GridColor', C.grid, ...
        'FontSize', 13, 'LineWidth', 1, 'Box', 'on', 'XGrid', 'off', 'YGrid', 'on');
end

function labelAxes(ax, C, ttl, xl, yl)
title(ax, ttl, 'Color', C.ink, 'FontSize', 16, 'FontWeight', 'bold');
xlabel(ax, xl, 'Color', C.ink, 'FontSize', 14);
ylabel(ax, yl, 'Color', C.ink, 'FontSize', 14);
end

function styleLegend(lg, C)
try, set(lg, 'TextColor', C.ink, 'Color', 'w', 'EdgeColor', C.grid, 'FontSize', 12); catch, end
end

function drawGraph(ax, D, M, k, C)
cla(ax, 'reset');  hold(ax, 'on');  styleAxes(ax, C);
nm = rowNames(D);
switch k
case 1  % calculated vs measured
    x = 1:10;  w = 0.38;
    calc = [M.F; NaN(3,1)];  sig = [M.sigF; NaN(3,1)];
    mm = M.measMean;  sd = M.measSD;
    hc = bar(ax, x(1:7) - w/2, calc(1:7), w, 'FaceColor', C.brown, 'EdgeColor', 'none');
    hm = bar(ax, [x(1:7) + w/2, x(8:10)], mm, w, 'FaceColor', C.gold, 'EdgeColor', C.goldDk);
    ok = isfinite(calc(1:7));
    xo = x(:);  he = errorbar(ax, xo(ok) - w/2, calc(ok), sig(ok));
    set(he, 'LineStyle', 'none', 'Color', C.ink, 'LineWidth', 1.4);
    xm = [x(1:7) + w/2, x(8:10)]';  okm = isfinite(mm);
    he = errorbar(ax, xm(okm), mm(okm), sd(okm));
    set(he, 'LineStyle', 'none', 'Color', C.ink, 'LineWidth', 1.4);
    top = max([calc + sig; mm + sd; 1]);
    for r = 1:7
        if isfinite(M.pctErr(r))
            text(x(r) + w/2, mm(r) + sd(r) + 0.04*top, sprintf('%.0f%%', M.pctErr(r)), 'Parent', ax, ...
                 'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold', 'Color', C.ink);
        end
    end
    line([7.5 7.5], [0 1.25*top], 'Parent', ax, 'Color', C.muted, 'LineStyle', '--');
    text(9, 1.17*top, 'Alternate jaws (measured only)', 'Parent', ax, 'HorizontalAlignment', 'center', ...
         'FontSize', 11, 'Color', C.muted);
    set(ax, 'XTick', x, 'XTickLabel', {nm{1:7}, 'Alt 1', 'Alt 2', 'Alt 3'});
    xlim(ax, [0.4 10.6]);  ylim(ax, [0 1.25*top]);
    labelAxes(ax, C, 'Calculated vs. measured jaw force', 'Muscle orientation', 'Load cell force (N)');
    lg = legend(ax, [hc hm], {'Calculated (\pm uncertainty)', 'Measured (mean \pm SD)'}, 'Location', 'northwest');
    styleLegend(lg, C);
case 2  % parity
    t = isfinite(M.F) & M.measN(1:7) > 0;
    top = 1.15 * max([M.F(t) + 2*M.sigF(t); M.measMean(t) + M.measSD(t); 1]);
    patch('Parent', ax, 'XData', [0; top; top; 0], 'YData', [0; 0.85*top; 1.15*top; 0], ...
          'FaceColor', C.gold, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    line([0 top], [0 top], 'Parent', ax, 'Color', C.muted, 'LineStyle', '--', 'LineWidth', 1.2);
    if any(t)
        he = errorbar(ax, M.F(t), M.measMean(t), M.measSD(t));
        set(he, 'LineStyle', 'none', 'Color', C.brown, 'LineWidth', 1.4, 'Marker', 'o', ...
                'MarkerSize', 8, 'MarkerFaceColor', C.brown);
        idx = find(t);
        for r = idx(:)'
            text(M.F(r) + 0.02*top, M.measMean(r), nm{r}, 'Parent', ax, 'FontSize', 13, ...
                 'FontWeight', 'bold', 'Color', C.ink);
        end
    end
    xlim(ax, [0 top]);  ylim(ax, [0 top]);  set(ax, 'DataAspectRatio', [1 1 1], 'XGrid', 'on');
    labelAxes(ax, C, 'Measured vs. calculated (shaded = within 15%)', 'Calculated force (N)', 'Measured force (N)');
    text(0.05*top, 0.93*top, 'Above the line: model underestimates', 'Parent', ax, 'FontSize', 11, 'Color', C.muted);
case 3  % angle sweep
    thv = 0:0.5:90;  hs = {};  used = {};
    for r = 1:7
        if ~M.valid(r), continue, end
        g = D.geom(r,:);
        F = M.FM(r) * (g(2)*cosd(thv) + g(3)*sind(thv)) / g(4);
        hs{end+1} = plot(ax, thv, F, 'Color', C.pal(r,:), 'LineWidth', 2.2);  %#ok<AGROW>
        used{end+1} = nm{r};  %#ok<AGROW>
        plot(ax, g(1), M.F(r), 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.pal(r,:), 'MarkerEdgeColor', 'w');
        plot(ax, M.thetaBest(r), M.Fbest(r), 'p', 'MarkerSize', 13, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.ink);
    end
    xlim(ax, [0 90]);  set(ax, 'XTick', 0:15:90, 'XGrid', 'on');
    labelAxes(ax, C, 'Force vs. muscle angle   (circle = your angle, star = best angle)', ...
              'Muscle angle from vertical, \theta (deg)', 'Predicted load cell force (N)');
    if ~isempty(hs)
        lg = legend(ax, [hs{:}], used, 'Location', 'eastoutside');  styleLegend(lg, C);
    end
case 4  % torque vs jaw opening
    ph = 0:0.5:30;  hs = {};  used = {};
    for r = 1:7
        if ~M.valid(r), continue, end
        tau = zeros(size(ph));
        for j = 1:numel(ph), K = jawKin(D, r, ph(j)); tau(j) = K.tau; end
        hs{end+1} = plot(ax, ph, tau, 'Color', C.pal(r,:), 'LineWidth', 2.2);  %#ok<AGROW>
        used{end+1} = nm{r};  %#ok<AGROW>
    end
    xlim(ax, [0 30]);  set(ax, 'XGrid', 'on');
    labelAxes(ax, C, 'Muscle torque about the pivot as the jaw opens', ...
              'Jaw opening angle \phi (deg), 0 = on the load cell', 'Torque \tau = r \times F (N\cdotmm)');
    if ~isempty(hs)
        lg = legend(ax, [hs{:}], used, 'Location', 'eastoutside');  styleLegend(lg, C);
    end
case 5  % sensitivity
    v = find(M.valid);
    if isempty(v), v = 1; end
    Y = 100 * M.groupFrac(v, :);
    if numel(v) == 1, Y = [Y; NaN(1,3)]; xs = [1 2]; else, xs = 1:numel(v); end
    hb = bar(ax, xs, Y, 'stacked', 'EdgeColor', 'w');
    cols = [C.brown; C.gold; C.pal(3,:)];
    for q = 1:3, set(hb(q), 'FaceColor', cols(q,:)); end
    set(ax, 'XTick', 1:numel(v), 'XTickLabel', nm(v));
    xlim(ax, [0.4 numel(v) + 0.6]);  ylim(ax, [0 100]);
    labelAxes(ax, C, 'Which measurement causes the most uncertainty?', 'Muscle orientation', '% of prediction uncertainty');
    lg = legend(ax, hb, M.groupNames, 'Location', 'eastoutside');  styleLegend(lg, C);
case 6  % least squares
    if isempty(M.fitU)
        text(0.5, 0.5, 'Enter measured forces to fit your muscle coefficient', 'Parent', ax, ...
             'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', C.muted);
        labelAxes(ax, C, 'Least-squares muscle coefficient', '', '');
    else
        umax = 1.1 * max(M.fitU);
        h1 = plot(ax, M.fitU, M.fitF, 'o', 'MarkerSize', 8, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown);
        h2 = plot(ax, [0 umax], [0 M.k*umax], '-', 'Color', C.brown, 'LineWidth', 2.4);
        h3 = plot(ax, [0 umax], [0 -D.a*umax], '--', 'Color', C.muted, 'LineWidth', 1.8);
        xlim(ax, [0 umax]);  ylim(ax, [0 1.15*max([M.fitF; M.k*umax; -D.a*umax])]);  set(ax, 'XGrid', 'on');
        labelAxes(ax, C, sprintf('Least-squares fit: a = %.2f N/mm  (R^2 = %.2f)', M.aFit, M.R2), ...
                  'Geometry term u (mm)', 'Measured load cell force (N)');
        lg = legend(ax, [h1 h2 h3], {'Measured squeezes', sprintf('Best fit, a = %.2f', M.aFit), ...
                    sprintf('Class value, a = %.2f', D.a)}, 'Location', 'northwest');
        styleLegend(lg, C);
    end
end
hold(ax, 'off');
end

function drawPressure(ax, D, P, mode, C)
% mode 1 = muscle force vs. pressure, mode 2 = bite (load cell) force vs. pressure
cla(ax, 'reset');  hold(ax, 'on');  styleAxes(ax, C);
if ~P.valid
    text(0.5, 0.5, 'Fill in this orientation and the muscle settings', 'Parent', ax, ...
         'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', C.muted);
    hold(ax, 'off');  return
end
xmax = D.Pmax;
if isfinite(P.Pimp), xmax = max(xmax, 1.1*P.Pimp); end
if ~isempty(P.Pm), xmax = max(xmax, 1.05*max(P.Pm)); end
Pv = linspace(0, xmax, 200);
hs = {};  nm = {};  yv = 1;
if mode == 1
    tot = 'Total (sum of both muscles)';
    if muscleFactor(D) == 0.5, tot = 'Average of both muscles'; end
    hs{end+1} = plot(ax, Pv, P.perMuscle(1)*Pv, '--', 'Color', C.pal(3,:), 'LineWidth', 1.8);
    nm{end+1} = sprintf('Muscle 1 (braid %.0f\\circ)', P.theta(1));
    hs{end+1} = plot(ax, Pv, P.perMuscle(2)*Pv, ':', 'Color', C.pal(4,:), 'LineWidth', 2.2);
    nm{end+1} = sprintf('Muscle 2 (braid %.0f\\circ)', P.theta(2));
    hs{end+1} = plot(ax, Pv, P.slopeM*Pv, '-', 'Color', C.brown, 'LineWidth', 2.8);
    nm{end+1} = tot;  yv = [yv, P.slopeM*xmax];
    if isfinite(P.kM)
        hs{end+1} = plot(ax, Pv, P.kM*P.slopeM*Pv, '-.', 'Color', C.pal(5,:), 'LineWidth', 2.2);
        nm{end+1} = sprintf('%s x k_M = %.2f (Tab 6)', tot, P.kM);
    end
    if isfinite(P.Pimp)
        hs{end+1} = plot(ax, P.Pimp, P.FM, 'p', 'MarkerSize', 15, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.ink);
        nm{end+1} = sprintf('Class model F_M = %.1f N (needs %.0f kPa)', P.FM, P.Pimp);
        yv = [yv, P.FM];
    end
    if ~isempty(P.Pm) && P.arm > 0
        Fmus = P.Fm * P.RLC / P.arm;
        hs{end+1} = plot(ax, P.Pm, Fmus, 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown);
        nm{end+1} = 'Measured (load cell \times R_{LC} / arm)';
        yv = [yv, max(Fmus)];
    end
    labelAxes(ax, C, 'Ideal McKibben muscle force vs. pressure', 'Gauge pressure P (kPa)', 'Muscle force F_M (N)');
else
    hs{end+1} = plot(ax, Pv, P.slopeLC*Pv, '-', 'Color', C.brown, 'LineWidth', 2.8);
    nm{end+1} = sprintf('Ideal theory: %.3f N per kPa', P.slopeLC);  yv = [yv, P.slopeLC*xmax];
    if isfinite(P.kM)
        hs{end+1} = plot(ax, Pv, P.kM*P.slopeLC*Pv, '-.', 'Color', C.pal(5,:), 'LineWidth', 2.2);
        nm{end+1} = sprintf('Theory \\times muscle factor k_M = %.2f (Tab 6)', P.kM);
    end
    if isfinite(P.k)
        hs{end+1} = plot(ax, Pv, P.k*P.slopeLC*Pv, '--', 'Color', C.goldDk, 'LineWidth', 2.2);
        nm{end+1} = sprintf('Theory \\times %.2f (fit to your readings)', P.k);
    end
    if isfinite(P.R2)
        hs{end+1} = plot(ax, Pv, polyval(P.fit, Pv), ':', 'Color', C.pal(3,:), 'LineWidth', 2.2);
        nm{end+1} = sprintf('Straight-line fit (R^2 = %.2f)', P.R2);
        yv = [yv, max(polyval(P.fit, Pv))];
    end
    if ~isempty(P.Pm)
        hs{end+1} = plot(ax, P.Pm, P.Fm, 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown);
        nm{end+1} = 'Measured load cell force';  yv = [yv, max(P.Fm)];
    end
    if isfinite(P.Pimp)
        hs{end+1} = plot(ax, P.Pimp, P.FLC, 'p', 'MarkerSize', 15, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.ink);
        nm{end+1} = sprintf('Class model F_{LC} = %.1f N', P.FLC);  yv = [yv, P.FLC];
    end
    labelAxes(ax, C, 'Bite force vs. pressure', 'Gauge pressure P (kPa)', 'Load cell force F_{LC} (N)');
end
xlim(ax, [0 xmax]);  ylim(ax, [0 1.12*max(yv)]);  set(ax, 'XGrid', 'on');
lg = legend(ax, [hs{:}], nm, 'Location', 'northwest');  styleLegend(lg, C);
hold(ax, 'off');
end

function drawCal(ax, D, Q, C)
% Step 1 graph: one muscle on the load cell, predicted vs. measured force.
cla(ax, 'reset');  hold(ax, 'on');  styleAxes(ax, C);
un = D.calUnit;
if ~Q.valid
    text(0.5, 0.5, 'Check the muscle settings on Tab 5', 'Parent', ax, 'Units', 'normalized', ...
         'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', C.muted);
    hold(ax, 'off');  return
end
xmax = max([D.peakP; Q.P; 1]) * 1.1;
Pv = linspace(0, xmax, 100);
hs = {};  nm = {};  yv = Q.perUnit * xmax;
hs{end+1} = plot(ax, Pv, Q.perUnit*Pv, '-', 'Color', C.brown, 'LineWidth', 2.6);
nm{end+1} = sprintf('Predicted (ideal): %.3f N/%s', Q.perUnit, un);
if isfinite(Q.kM)
    hs{end+1} = plot(ax, Pv, Q.kM*Q.perUnit*Pv, '--', 'Color', C.goldDk, 'LineWidth', 2.4);
    nm{end+1} = sprintf('Corrected: k_M = %.2f', Q.kM);
end
if Q.n > 0
    hs{end+1} = plot(ax, Q.P, Q.Fm, 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown);
    nm{end+1} = 'Measured (load cell)';  yv = [yv; Q.Fm(:)];
else
    text(0.5, 0.88, 'Type readings in the Step 1 table', 'Parent', ax, 'Units', 'normalized', ...
         'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', C.muted);
end
xlim(ax, [0 xmax]);  ylim(ax, [0 1.12*max(yv)]);  set(ax, 'XGrid', 'on');
labelAxes(ax, C, 'Step 1: one muscle on the load cell', sprintf('Peak pressure (%s)', un), 'Muscle force (N)');
lg = legend(ax, [hs{:}], nm, 'Location', 'northwest');  styleLegend(lg, C);
hold(ax, 'off');
end

function drawDecay(ax, D, T, C)
% Step 2 graph: pressure vs. time and the fitted time constant.
cla(ax, 'reset');  hold(ax, 'on');  styleAxes(ax, C);
un = D.calUnit;
if T.n == 0
    text(0.5, 0.5, 'Type time and pressure readings in the Step 2 table', 'Parent', ax, ...
         'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontSize', 13, 'Color', C.muted);
    labelAxes(ax, C, 'Step 2: pressure time constant', 'Time (s)', sprintf('Pressure (%s)', un));
    hold(ax, 'off');  return
end
tmin = min(T.t);  tmax = max(T.t);  if tmax <= tmin, tmax = tmin + 1; end
hs = {};  nm = {};  yv = T.p(:);
hs{end+1} = plot(ax, T.t, T.p, 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown);
nm{end+1} = 'Sensor readings';
if isfinite(T.tau)
    tv = linspace(tmin, tmax, 200);  T = decayCurve(T, tv);
    hs{end+1} = plot(ax, tv, T.curve, '-', 'Color', C.brown, 'LineWidth', 2.6);
    nm{end+1} = sprintf('Fit: \\tau = %.1f s  (R^2 = %.3f)', T.tau, T.R2);
    yv = [yv; T.curve(:)];
    if ~T.rising && isfinite(T.loss)
        % shade one squeeze, starting at the first reading
        tq = linspace(tmin, min(tmin + T.tHold, tmax), 30);  Tq = decayCurve(T, tq);
        patch('Parent', ax, 'XData', [tq, fliplr(tq)], 'YData', [Tq.curve, zeros(size(tq))], ...
              'FaceColor', C.gold, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
        text(tmin + 0.02*(tmax - tmin), 0.08*max(yv), sprintf('one %.1f s squeeze: %.1f%% force lost', ...
             T.tHold, 100*T.loss), 'Parent', ax, 'FontSize', 11, 'Color', C.ink);
    end
end
xlim(ax, [tmin tmax]);  ylim(ax, [0 1.12*max(yv)]);  set(ax, 'XGrid', 'on');
labelAxes(ax, C, 'Step 2: pressure time constant', 'Time (s)', sprintf('Pressure (%s)', un));
loc = 'northeast';  if T.rising, loc = 'southeast'; end
lg = legend(ax, [hs{:}], nm, 'Location', loc);  styleLegend(lg, C);
hold(ax, 'off');
end

function drawArrow(ax, p, v, col, lw)
L = norm(v);
if L < 1e-9, return, end
u = v / L;  n = [-u(2); u(1)];  hl = min(0.35*L, 7);  hw = 0.55*hl;
tip = p + v;  base = tip - hl*u;
line([p(1) base(1)], [p(2) base(2)], 'Parent', ax, 'Color', col, 'LineWidth', lw);
patch('Parent', ax, 'XData', [tip(1); base(1) + hw*n(1); base(1) - hw*n(1)], ...
      'YData', [tip(2); base(2) + hw*n(2); base(2) - hw*n(2)], 'FaceColor', col, 'EdgeColor', col);
end

function drawJaw(ax, D, i, phiDeg, C)
cla(ax, 'reset');  hold(ax, 'on');
set(ax, 'Color', 'w', 'XTick', [], 'YTick', [], 'XColor', 'w', 'YColor', 'w', 'Box', 'off');
nm = rowNames(D);
M = computeModel(D);
if ~M.valid(i)
    text(0.5, 0.5, 'Fill in this orientation on the Jaw setup tab', 'Parent', ax, 'Units', 'normalized', ...
         'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', C.muted);
    hold(ax, 'off');  return
end
g = D.geom(i,:);  RMX = g(2);  RMY = g(3);  RLC = g(4);
K = jawKin(D, i, phiDeg);  K0 = jawKin(D, i, 0);
Hlc = 18;  S = K.S;

% skull / upper jaw (fixed)
xb = min(-38, S(1) - 32);
sk = [ -22 -6; xb 0.55*S(2); S(1)-22 S(2)+14; S(1)+30 S(2)+16; max(S(1)+40, 0.8*RLC) Hlc+48; ...
       RLC+16 Hlc+24; RLC+16 Hlc; RMX+22 Hlc; 10 9 ];
patch('Parent', ax, 'XData', sk(:,1), 'YData', sk(:,2), 'FaceColor', C.skull, 'EdgeColor', C.muted, 'LineWidth', 1.2);

% load cell
patch('Parent', ax, 'XData', RLC + [-8; 8; 8; -8], 'YData', [0; 0; Hlc; Hlc], 'FaceColor', C.cell, 'EdgeColor', C.ink);
text(RLC + 19, Hlc + 12, 'Load cell', 'Parent', ax, 'FontSize', 11, 'Color', C.ink);

% lower jaw (rotates about the pivot)
jw = [ -14 -13; RLC+13 -13; RLC+13 0; RMX+10 0; RMX+5 RMY+6; RMX-5 RMY+6; RMX-10 0; -14 0 ]';
jw = K.R * jw;
patch('Parent', ax, 'XData', jw(1,:)', 'YData', jw(2,:)', 'FaceColor', C.jaw, 'EdgeColor', C.brown, 'LineWidth', 1.5);

% muscle
line([K.P(1) S(1)], [K.P(2) S(2)], 'Parent', ax, 'Color', C.muscle, 'LineWidth', 9);
line([K.P(1) S(1)], [K.P(2) S(2)], 'Parent', ax, 'Color', [0.45 0.6 0.3], 'LineWidth', 2, 'LineStyle', ':');
plot(ax, [K.P(1) S(1)], [K.P(2) S(2)], 's', 'MarkerSize', 8, 'MarkerFaceColor', C.cell, 'MarkerEdgeColor', C.ink);

% pivot
th = linspace(0, 2*pi, 30);
patch('Parent', ax, 'XData', 4*cos(th(:)), 'YData', 4*sin(th(:)), 'FaceColor', C.ink, 'EdgeColor', C.ink);
text(-6, -20, 'Pivot A', 'Parent', ax, 'FontSize', 11, 'Color', C.ink, 'HorizontalAlignment', 'right');

% force arrows (scaled to the closed-jaw muscle force)
sc = 45 / max(K0.FM, 1);
drawArrow(ax, K.P, K.Fvec * sc, C.brown, 3);
text(K.P(1) + K.Fvec(1)*sc + 4, K.P(2) + K.Fvec(2)*sc, sprintf('F_M = %.1f N', K.FM), 'Parent', ax, ...
     'FontSize', 12, 'FontWeight', 'bold', 'Color', C.brown);
if phiDeg < 0.25
    Lb = max(14, K.Fbite * sc);
    drawArrow(ax, [RLC + 24; Lb - 4], [0; -Lb], C.goldDk, 3);
    text(RLC + 28, Lb*0.35 - 8, sprintf('F_{LC} = %.1f N', K.Fbite), 'Parent', ax, 'FontSize', 12, ...
         'FontWeight', 'bold', 'Color', C.goldDk);
end

% torque arc
arc = linspace(-0.5, 1.9, 30);  rA = 13;
line(rA*cos(arc), rA*sin(arc), 'Parent', ax, 'Color', C.pal(3,:), 'LineWidth', 2);
tp = [rA*cos(arc(end)); rA*sin(arc(end))];  tv = [-sin(arc(end)); cos(arc(end))];
drawArrow(ax, tp - 4*tv, 4*tv, C.pal(3,:), 2);
text(-20, 18, sprintf('\\tau = %.0f N\\cdotmm', K.tau), 'Parent', ax, 'FontSize', 12, ...
     'FontWeight', 'bold', 'Color', C.pal(3,:), 'HorizontalAlignment', 'right');

axis(ax, 'equal');
xlim(ax, [min(xb, -60) - 10, RLC + 80]);
ylim(ax, [-(RLC + 14)*sind(30) - 20, S(2) + 26]);
title(ax, sprintf('Orientation %s   |   jaw opening \\phi = %.1f\\circ', nm{i}, phiDeg), ...
      'Color', C.ink, 'FontSize', 15, 'FontWeight', 'bold');
hold(ax, 'off');
end

function drawTorque(ax, D, i, phiDeg, C)
cla(ax, 'reset');  hold(ax, 'on');  styleAxes(ax, C);
M = computeModel(D);
if ~M.valid(i), hold(ax, 'off'); return, end
ph = 0:0.5:30;  tau = zeros(size(ph));  Fb = tau;
for j = 1:numel(ph), K = jawKin(D, i, ph(j)); tau(j) = K.tau; Fb(j) = K.Fbite; end
K = jawKin(D, i, phiDeg);
plot(ax, ph, tau, 'Color', C.brown, 'LineWidth', 2.6);
plot(ax, phiDeg, K.tau, 'o', 'MarkerSize', 11, 'MarkerFaceColor', C.gold, 'MarkerEdgeColor', C.brown, 'LineWidth', 1.5);
xlim(ax, [0 30]);  set(ax, 'XGrid', 'on');
labelAxes(ax, C, 'Muscle torque vs. jaw opening', 'Jaw opening \phi (deg)', 'Torque \tau (N\cdotmm)');
hold(ax, 'off');
end

% =========================================================================
%  THE APP WINDOW
% =========================================================================

function buildApp()
C = appColors();
fig = uifigure('Name', 'JAWS: Force & Torque Model', 'Position', [60 50 1280 800], 'Color', 'w');
try, theme(fig, 'light'); catch, end   % keeps R2025a+ dark mode from recoloring the app

A.C = C;  A.D = exampleData();  A.phi = 0;  A.graph = 1;  A.playing = false;

root = uigridlayout(fig, [2 1]);
root.RowHeight = {44, '1x'};  root.Padding = [12 8 12 12];  root.BackgroundColor = 'w';
hdr = uilabel(root, 'Text', 'JAWS: Force & Torque Model', 'FontSize', 22, 'FontWeight', 'bold', 'FontColor', C.brown);
hdr.Layout.Row = 1;
tg = uitabgroup(root);  tg.Layout.Row = 2;

% ---------- Tab 1: setup ----------
t1 = uitab(tg, 'Title', '  1. Jaw setup  ', 'BackgroundColor', 'w');
g1 = uigridlayout(t1, [1 2]);  g1.ColumnWidth = {330, '1x'};  g1.BackgroundColor = 'w';
p1 = uipanel(g1, 'Title', 'Team settings', 'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', 'w');
gp = uigridlayout(p1, [12 2]);  gp.ColumnWidth = {150, '1x'};
gp.RowHeight = {30, 30, 30, 30, 30, 30, 10, 36, 36, 36, 36, '1x'};  gp.BackgroundColor = 'w';
mkLabel(gp, 'Team name', 1);
A.h.team = uieditfield(gp, 'text', 'Value', A.D.team, 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.team.Layout.Row = 1;  A.h.team.Layout.Column = 2;
mkLabel(gp, 'Muscle force', 2);
A.h.mode = uidropdown(gp, 'Items', {'Sum of both', 'Average of both'}, 'FontSize', 13, ...
                      'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.mode.Layout.Row = 2;  A.h.mode.Layout.Column = 2;
mkLabel(gp, 'Muscle coeff. a (N/mm)', 3);
A.h.a = uieditfield(gp, 'numeric', 'Value', A.D.a, 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.a.Layout.Row = 3;  A.h.a.Layout.Column = 2;
mkLabel(gp, 'Length uncert. (mm)', 4);
A.h.sL = uieditfield(gp, 'numeric', 'Value', A.D.sigLen, 'Limits', [0 50], 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.sL.Layout.Row = 4;  A.h.sL.Layout.Column = 2;
mkLabel(gp, 'Distance uncert. (mm)', 5);
A.h.sA = uieditfield(gp, 'numeric', 'Value', A.D.sigArm, 'Limits', [0 50], 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.sA.Layout.Row = 5;  A.h.sA.Layout.Column = 2;
mkLabel(gp, 'Angle uncert. (deg)', 6);
A.h.sT = uieditfield(gp, 'numeric', 'Value', A.D.sigTheta, 'Limits', [0 45], 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSettings(fig));
A.h.sT.Layout.Row = 6;  A.h.sT.Layout.Column = 2;
b = mkButton(gp, 'Save team file', @(s,e) onSaveTeam(fig), C, true);   b.Layout.Row = 8;  b.Layout.Column = [1 2];
b = mkButton(gp, 'Open team file', @(s,e) onOpenTeam(fig), C, false); b.Layout.Row = 9;  b.Layout.Column = [1 2];
b = mkButton(gp, 'Load example numbers', @(s,e) onExample(fig), C, false); b.Layout.Row = 10; b.Layout.Column = [1 2];
b = mkButton(gp, 'Show the math', @(s,e) onShowMath(fig), C, false); b.Layout.Row = 11; b.Layout.Column = [1 2];

r1 = uigridlayout(g1, [3 1]);  r1.RowHeight = {48, 300, '1x'};  r1.BackgroundColor = 'w';
A.h.banner = uilabel(r1, 'Text', '', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.brown);
A.h.geom = uitable(r1, 'Data', A.D.geom, 'FontSize', 13, 'RowName', A.D.labels, ...
    'ColumnName', {'Angle theta (deg)', 'R_MX (mm)', 'R_MY (mm)', 'R_LC (mm)', 'b1 (mm)', 'b2 (mm)', 'x1 (mm)', 'x2 (mm)'}, ...
    'ColumnEditable', true(1, 8), 'CellEditCallback', @(s,e) onGeomEdit(fig));
help1 = uilabel(r1, 'FontSize', 13, 'FontColor', C.ink, 'VerticalAlignment', 'top', 'Text', { ...
    'What each column means (measure from your free-body diagram, in mm):', ...
    '   Angle theta: how far the muscle tilts from straight up and down', ...
    '   R_MX: sideways distance from the jaw hinge (pivot A) to where the muscle force acts', ...
    '   R_MY: up-and-down distance from the hinge to where the muscle force acts', ...
    '   R_LC: distance from the hinge to where the jaw presses the load cell', ...
    '   b1, b2: how much each muscle shortens with NO load attached', ...
    '   x1, x2: how much each muscle shortens while attached and pressing the load cell', ...
    'Click a cell and type to change it. Everything updates automatically.'});
help1.Layout.Row = 3;

% ---------- Tab 2: measured ----------
t2 = uitab(tg, 'Title', '  2. Measured forces  ', 'BackgroundColor', 'w');
g2 = uigridlayout(t2, [1 2]);  g2.ColumnWidth = {'1x', 360};  g2.BackgroundColor = 'w';
l2 = uigridlayout(g2, [2 1]);  l2.RowHeight = {40, '1x'};  l2.BackgroundColor = 'w';
uilabel(l2, 'Text', 'Type each load cell reading in newtons (up to 5 squeezes per row).', ...
        'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
A.h.meas = uitable(l2, 'Data', measToCell(A.D.meas), 'FontSize', 13, 'RowName', rowNames(A.D), ...
    'ColumnName', {'Squeeze 1', 'Squeeze 2', 'Squeeze 3', 'Squeeze 4', 'Squeeze 5'}, ...
    'ColumnEditable', true(1, 5), 'ColumnFormat', repmat({'char'}, 1, 5), 'CellEditCallback', @(s,e) onMeasEdit(fig));
p2 = uipanel(g2, 'Title', 'Import from the leaderboard', 'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', 'w');
gi = uigridlayout(p2, [6 2]);  gi.RowHeight = {30, 30, 40, 10, 40, '1x'};  gi.ColumnWidth = {110, '1x'};  gi.BackgroundColor = 'w';
mkLabel(gi, 'Class name', 1);
A.h.cls = uieditfield(gi, 'text', 'Value', 'main', 'FontSize', 13);  A.h.cls.Layout.Row = 1;  A.h.cls.Layout.Column = 2;
mkLabel(gi, 'Team slot', 2);
A.h.slot = uidropdown(gi, 'Items', arrayfun(@(k) sprintf('team%d', k), 1:10, 'UniformOutput', false), 'FontSize', 13);
A.h.slot.Layout.Row = 2;  A.h.slot.Layout.Column = 2;
b = mkButton(gi, 'Import JSON file...', @(s,e) onImport(fig), C, true);  b.Layout.Row = 3;  b.Layout.Column = [1 2];
b = mkButton(gi, 'Clear all measured forces', @(s,e) onClearMeas(fig), C, false);  b.Layout.Row = 5;  b.Layout.Column = [1 2];
hi = uilabel(gi, 'FontSize', 12, 'FontColor', C.ink, 'VerticalAlignment', 'top', 'Text', { ...
    'How to get the JSON file:', ...
    '1. Open the Firebase console for the', '    leaderboard.', ...
    '2. Go to Realtime Database.', ...
    '3. Click the three-dot menu and', '    choose Export JSON.', ...
    '4. Click Import JSON file above and', '    pick the downloaded file.', ...
    '', 'Class name is the ?class= name used', 'in class ("main" if none).', ...
    'Team slot is the slot your team', 'picked on the station page.', ...
    'The 5 most recent squeezes per row', 'are imported.'});
hi.Layout.Row = 6;  hi.Layout.Column = [1 2];

% ---------- Tab 3: simulation ----------
t3 = uitab(tg, 'Title', '  3. Jaw simulation  ', 'BackgroundColor', 'w');
g3 = uigridlayout(t3, [3 1]);  g3.RowHeight = {44, '1x', 36};  g3.BackgroundColor = 'w';
c3 = uigridlayout(g3, [1 6]);  c3.ColumnWidth = {100, 90, 120, '1x', 90, 150};  c3.Padding = [0 0 0 0];  c3.BackgroundColor = 'w';
uilabel(c3, 'Text', 'Orientation', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
A.h.ori = uidropdown(c3, 'Items', A.D.labels, 'FontSize', 14, 'ValueChangedFcn', @(s,e) onOri(fig));
A.h.play = mkButton(c3, 'Play', @(s,e) onPlay(fig), C, true);
A.h.slider = uislider(c3, 'Limits', [0 30], 'Value', 0, 'MajorTicks', 0:5:30, 'FontSize', 12, ...
    'ValueChangingFcn', @(s,e) onSlide(fig, e.Value), 'ValueChangedFcn', @(s,e) onSlide(fig, s.Value));
uilabel(c3, 'Text', 'opening (deg)', 'FontSize', 12, 'FontColor', C.muted);
mkButton(c3, 'Show the math', @(s,e) onShowMath(fig), C, false);
a3 = uigridlayout(g3, [1 2]);  a3.ColumnWidth = {'1.25x', '1x'};  a3.BackgroundColor = 'w';  a3.Padding = [0 0 0 0];
A.h.jawAx = uiaxes(a3);  A.h.torqueAx = uiaxes(a3);
A.h.readout = uilabel(g3, 'Text', '', 'FontSize', 14, 'FontColor', C.ink, 'FontWeight', 'bold');

% ---------- Tab 4: results ----------
t4 = uitab(tg, 'Title', '  4. Results  ', 'BackgroundColor', 'w');
g4 = uigridlayout(t4, [3 1]);  g4.RowHeight = {44, '1x', 210};  g4.BackgroundColor = 'w';
c4 = uigridlayout(g4, [1 5]);  c4.ColumnWidth = {60, 330, 170, 250, 150};  c4.Padding = [0 0 0 0];  c4.BackgroundColor = 'w';
uilabel(c4, 'Text', 'Graph', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
A.h.graph = uidropdown(c4, 'Items', graphNames(), 'FontSize', 13, 'ValueChangedFcn', @(s,e) onGraph(fig));
mkButton(c4, 'Save this graph', @(s,e) onSaveGraph(fig), C, false);
mkButton(c4, 'Save all graphs + Excel', @(s,e) onSaveAll(fig), C, true);
mkButton(c4, 'Show the math', @(s,e) onShowMath(fig), C, false);
A.h.resAx = uiaxes(g4);
A.h.res = uitable(g4, 'Data', resultsCell(A.D, computeModel(A.D)), 'ColumnName', resultsHeader(), ...
                  'RowName', {}, 'FontSize', 12);

% ---------- Tab 5: force vs. pressure ----------
t5 = uitab(tg, 'Title', '  5. Force vs. pressure  ', 'BackgroundColor', 'w');
g5 = uigridlayout(t5, [1 2]);  g5.ColumnWidth = {370, '1x'};  g5.BackgroundColor = 'w';
p5 = uipanel(g5, 'Title', 'Muscle and pressure', 'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', 'w');
gq = uigridlayout(p5, [13 2]);  gq.ColumnWidth = {195, '1x'};  gq.BackgroundColor = 'w';
gq.RowHeight = {28, 28, 28, 28, 28, 28, 4, 22, 240, 22, 28, 28, 24};  gq.RowSpacing = 6;
try, gq.Scrollable = 'on'; catch, end   % scroll instead of cutting off on small screens
onP = @(s,e) onPressSettings(fig);
mkLabel(gq, 'Orientation', 1);
A.h.pOri = uidropdown(gq, 'Items', A.D.labels, 'Value', A.D.labels{A.D.pressOri}, 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pOri.Layout.Row = 1;  A.h.pOri.Layout.Column = 2;
mkLabel(gq, 'Graph', 2);
A.h.pGraph = uidropdown(gq, 'Items', {'Bite force', 'Muscle force'}, 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pGraph.Layout.Row = 2;  A.h.pGraph.Layout.Column = 2;
mkLabel(gq, 'Diameter D0 (mm)', 3);
A.h.pD0 = uieditfield(gq, 'numeric', 'Value', A.D.D0, 'Limits', [0.1 100], 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pD0.Layout.Row = 3;  A.h.pD0.Layout.Column = 2;
mkLabel(gq, 'Relaxed braid angle (deg)', 4);
A.h.pTh0 = uieditfield(gq, 'numeric', 'Value', A.D.braid0, 'Limits', [1 54.7], 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pTh0.Layout.Row = 4;  A.h.pTh0.Layout.Column = 2;
mkLabel(gq, 'Relaxed muscle length (mm)', 5);
A.h.pL = uieditfield(gq, 'numeric', 'Value', A.D.Lm, 'Limits', [1 1000], 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pL.Layout.Row = 5;  A.h.pL.Layout.Column = 2;
mkLabel(gq, 'Graph up to (kPa)', 6);
A.h.pMax = uieditfield(gq, 'numeric', 'Value', A.D.Pmax, 'Limits', [1 2000], 'FontSize', 13, 'ValueChangedFcn', onP);
A.h.pMax.Layout.Row = 6;  A.h.pMax.Layout.Column = 2;
l = uilabel(gq, 'Text', 'Readings in this orientation (psi x 6.895 = kPa)', 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', C.ink);
l.Layout.Row = 8;  l.Layout.Column = [1 2];
A.h.pTab = uitable(gq, 'Data', measToCell(A.D.press), 'FontSize', 13, ...
    'ColumnName', {'Pressure (kPa)', 'Load cell (N)'}, 'ColumnEditable', [true true], ...
    'ColumnFormat', {'char', 'char'}, 'CellEditCallback', @(s,e) onPressEdit(fig));
A.h.pTab.Layout.Row = 9;  A.h.pTab.Layout.Column = [1 2];
l = uilabel(gq, 'Text', 'No gauge? Estimate it from the syringe:', 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', C.ink);
l.Layout.Row = 10;  l.Layout.Column = [1 2];
mkLabel(gq, 'Sealed air volume (mL)', 11);
A.h.sV0 = uieditfield(gq, 'numeric', 'Value', 60, 'Limits', [0.1 1000], 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSyringe(fig));
A.h.sV0.Layout.Row = 11;  A.h.sV0.Layout.Column = 2;
mkLabel(gq, 'Pushed to (mL)', 12);
A.h.sV = uieditfield(gq, 'numeric', 'Value', 40, 'Limits', [0.1 1000], 'FontSize', 13, 'ValueChangedFcn', @(s,e) onSyringe(fig));
A.h.sV.Layout.Row = 12;  A.h.sV.Layout.Column = 2;
A.h.sOut = uilabel(gq, 'Text', '', 'FontSize', 13, 'FontWeight', 'bold', 'FontColor', C.brown);
A.h.sOut.Layout.Row = 13;  A.h.sOut.Layout.Column = [1 2];
r5 = uigridlayout(g5, [3 1]);  r5.RowHeight = {36, '1x', 100};  r5.BackgroundColor = 'w';  r5.Padding = [0 0 0 0];
c5 = uigridlayout(r5, [1 3]);  c5.ColumnWidth = {'1x', 170, 150};  c5.Padding = [0 0 0 0];  c5.BackgroundColor = 'w';
uilabel(c5, 'Text', ['Ideal McKibben equation:   F = (' char(960) ' D0' char(178) ' P / 4)(3 cos' char(178) char(952) ' - 1)'], ...
        'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
mkButton(c5, 'Save this graph', @(s,e) onSavePressGraph(fig), C, false);
mkButton(c5, 'Show the math', @(s,e) onShowMath(fig), C, false);
A.h.pAx = uiaxes(r5);
A.h.pSum = uilabel(r5, 'Text', '', 'FontSize', 13, 'FontColor', C.ink, 'VerticalAlignment', 'top');

% ---------- Tab 6: pressure calibration (Week 9 plan) ----------
t6 = uitab(tg, 'Title', '  6. Pressure calibration  ', 'BackgroundColor', 'w');
g6 = uigridlayout(t6, [1 2]);  g6.ColumnWidth = {370, '1x'};  g6.BackgroundColor = 'w';
p6 = uipanel(g6, 'Title', 'Sensor readings', 'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', 'w');
gc = uigridlayout(p6, [14 2]);  gc.ColumnWidth = {185, '1x'};  gc.BackgroundColor = 'w';
gc.RowHeight = {28, 22, 28, 170, 22, 28, 28, 210, 22, 28, 28, 36, 36, 4};  gc.RowSpacing = 6;
try, gc.Scrollable = 'on'; catch, end
onC = @(s,e) onCalSettings(fig);
mkLabel(gc, 'Pressure units', 1);
A.h.cUnit = uidropdown(gc, 'Items', {'psi', 'kPa'}, 'Value', A.D.calUnit, 'FontSize', 13, ...
                       'ValueChangedFcn', @(s,e) onCalUnit(fig));
A.h.cUnit.Layout.Row = 1;  A.h.cUnit.Layout.Column = 2;
l = uilabel(gc, 'Text', 'Step 1: one muscle pulling straight on the load cell', 'FontSize', 12, ...
            'FontWeight', 'bold', 'FontColor', C.brown);
l.Layout.Row = 2;  l.Layout.Column = [1 2];
mkLabel(gc, 'Muscle shortening (mm)', 3);
A.h.cX = uieditfield(gc, 'numeric', 'Value', A.D.calX, 'Limits', [0 500], 'FontSize', 13, 'ValueChangedFcn', onC);
A.h.cX.Layout.Row = 3;  A.h.cX.Layout.Column = 2;
A.h.cTab = uitable(gc, 'Data', measToCell(A.D.cal), 'FontSize', 13, ...
    'ColumnName', {['Peak pressure (' A.D.calUnit ')'], 'Load cell (N)'}, 'ColumnEditable', [true true], ...
    'ColumnFormat', {'char', 'char'}, 'CellEditCallback', @(s,e) onCalEdit(fig));
A.h.cTab.Layout.Row = 4;  A.h.cTab.Layout.Column = [1 2];
l = uilabel(gc, 'Text', 'Step 2: pressure vs. time after pressurizing', 'FontSize', 12, ...
            'FontWeight', 'bold', 'FontColor', C.brown);
l.Layout.Row = 5;  l.Layout.Column = [1 2];
mkLabel(gc, 'Curve type', 6);
A.h.dMode = uidropdown(gc, 'Items', {'Leak-down (to 0)', 'Fill or settle'}, 'FontSize', 13, 'ValueChangedFcn', onC);
A.h.dMode.Value = A.h.dMode.Items{A.D.decayMode};
A.h.dMode.Layout.Row = 6;  A.h.dMode.Layout.Column = 2;
mkLabel(gc, 'One squeeze lasts (s)', 7);
A.h.dHold = uieditfield(gc, 'numeric', 'Value', A.D.tHold, 'Limits', [0 600], 'FontSize', 13, 'ValueChangedFcn', onC);
A.h.dHold.Layout.Row = 7;  A.h.dHold.Layout.Column = 2;
A.h.dTab = uitable(gc, 'Data', measToCell(A.D.decay), 'FontSize', 13, ...
    'ColumnName', {'Time (s)', ['Pressure (' A.D.calUnit ')']}, 'ColumnEditable', [true true], ...
    'ColumnFormat', {'char', 'char'}, 'CellEditCallback', @(s,e) onDecayEdit(fig));
A.h.dTab.Layout.Row = 8;  A.h.dTab.Layout.Column = [1 2];
l = uilabel(gc, 'Text', 'Step 3: predict the jaw force from a peak pressure', 'FontSize', 12, ...
            'FontWeight', 'bold', 'FontColor', C.brown);
l.Layout.Row = 9;  l.Layout.Column = [1 2];
mkLabel(gc, 'Orientation', 10);
A.h.cOri = uidropdown(gc, 'Items', A.D.labels, 'Value', A.D.labels{A.D.pressOri}, 'FontSize', 13, ...
                      'ValueChangedFcn', @(s,e) onCalOri(fig));
A.h.cOri.Layout.Row = 10;  A.h.cOri.Layout.Column = 2;
A.h.cPeakLbl = mkLabel(gc, sprintf('Peak pressure (%s)', A.D.calUnit), 11);
A.h.cPeak = uieditfield(gc, 'numeric', 'Value', A.D.peakP, 'Limits', [0 10000], 'FontSize', 13, 'ValueChangedFcn', onC);
A.h.cPeak.Layout.Row = 11;  A.h.cPeak.Layout.Column = 2;
b = mkButton(gc, 'Clear Step 1 and 2 tables', @(s,e) onClearCal(fig), C, false);  b.Layout.Row = 12;  b.Layout.Column = [1 2];
b = mkButton(gc, 'Save these graphs', @(s,e) onSaveCalGraphs(fig), C, false);   b.Layout.Row = 13;  b.Layout.Column = [1 2];
r6 = uigridlayout(g6, [3 1]);  r6.RowHeight = {36, '1x', 150};  r6.BackgroundColor = 'w';  r6.Padding = [0 0 0 0];
c6 = uigridlayout(r6, [1 2]);  c6.ColumnWidth = {'1x', 150};  c6.Padding = [0 0 0 0];  c6.BackgroundColor = 'w';
A.h.cBanner = uilabel(c6, 'Text', 'Peak pressure -> predicted force XX,  measured force YY,  correction factor = YY / XX', ...
                      'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
mkButton(c6, 'Show the math', @(s,e) onShowMath(fig), C, false);
a6 = uigridlayout(r6, [1 2]);  a6.BackgroundColor = 'w';  a6.Padding = [0 0 0 0];
A.h.calAx = uiaxes(a6);  A.h.decAx = uiaxes(a6);
A.h.cSum = uilabel(r6, 'Text', '', 'FontSize', 13, 'FontColor', C.ink, 'VerticalAlignment', 'top');

fig.UserData = A;
onSyringe(fig);
refreshAll(fig);
end

function l = mkLabel(parent, txt, row)
l = uilabel(parent, 'Text', txt, 'FontSize', 13, 'FontColor', [0.13 0.09 0.08]);
l.Layout.Row = row;  l.Layout.Column = 1;
end

function b = mkButton(parent, txt, cb, C, primary)
if primary
    b = uibutton(parent, 'push', 'Text', txt, 'ButtonPushedFcn', cb, 'FontSize', 13, 'FontWeight', 'bold', ...
                 'BackgroundColor', C.brown, 'FontColor', 'w');
else
    b = uibutton(parent, 'push', 'Text', txt, 'ButtonPushedFcn', cb, 'FontSize', 13, ...
                 'BackgroundColor', [0.96 0.94 0.90], 'FontColor', C.ink);
end
end

function c = measToCell(m)
c = repmat({''}, size(m));
for k = find(isfinite(m))', c{k} = sprintf('%g', m(k)); end
end

function m = cellToMeas(c)
m = NaN(size(c));
for k = 1:numel(c)
    v = c{k};
    if ischar(v) || isstring(v), v = str2double(v); end
    if isnumeric(v) && isscalar(v) && isfinite(v), m(k) = v; end
end
end

% ---------- refresh ----------
function refreshAll(fig)
A = fig.UserData;  M = computeModel(A.D);
if A.D.isExample
    A.h.banner.Text = 'Showing example numbers. Replace them with your team''s measurements.';
else
    A.h.banner.Text = sprintf('Team: %s', A.D.team);
end
A.h.res.Data = resultsCell(A.D, M);
drawGraph(A.h.resAx, A.D, M, A.graph, A.C);
drawSim(fig);
drawPressureTab(fig);
drawCalTab(fig);
end

function drawPressureTab(fig)
A = fig.UserData;  D = A.D;  M = computeModel(D);  i = D.pressOri;
P = pressureModel(D, M, i);
mode = 2;  if strcmp(A.h.pGraph.Value, 'Muscle force'), mode = 1; end
drawPressure(A.h.pAx, D, P, mode, A.C);
if ~P.valid
    A.h.pSum.Text = 'Fill in this orientation on the Jaw setup tab.';  return
end
L = {sprintf(['Ideal theory, orientation %s:  %.3f N of muscle force per kPa  ->  %.3f N of bite force per kPa' ...
              '   (braid angle at the load cell: %.1f and %.1f deg)'], D.labels{i}, P.slopeM, P.slopeLC, P.theta(1), P.theta(2))};
if isfinite(P.Pimp)
    L{end+1} = sprintf('Class model F_M = %.1f N  ->  an ideal muscle needs about %.0f kPa (%.0f psi) to make it.', ...
                       P.FM, P.Pimp, P.Pimp/6.895);
end
L{end+1} = sprintf('Ideal no-load contraction b = %.1f mm   (your b1, b2 = %.1f, %.1f mm)', P.bTheory, P.b(1), P.b(2));
if isfinite(P.k)
    s = sprintf('Your readings: measured = %.0f%% of ideal theory', 100*P.k);
    if isfinite(P.R2)
        s = sprintf('%s   |   straight-line fit: F_LC = %.4f P + %.2f  (R^2 = %.3f)', s, P.fit(1), P.fit(2), P.R2);
    end
    L{end+1} = s;
else
    L{end+1} = 'Type pressure and load cell readings in the table to compare them with the theory.';
end
if isfinite(P.kJ)
    L{end+1} = sprintf(['With the Tab 6 muscle factor k_M = %.2f the prediction is off by %.0f%% on average; ' ...
                        'jaw factor k_J = %.2f (losses in the jaw itself).'], P.kM, P.errCorr, P.kJ);
end
A.h.pSum.Text = L;
end

function drawCalTab(fig)
A = fig.UserData;  D = A.D;  M = computeModel(D);
Q = calModel(D);  T = decayModel(D);  R = peakPredict(D, M, D.pressOri);
drawCal(A.h.calAx, D, Q, A.C);
drawDecay(A.h.decAx, D, T, A.C);
un = D.calUnit;  L = {};
if D.calIsExample
    L{end+1} = 'Showing example numbers. Replace them with your sensor readings (or press Clear).';
end
if isfinite(Q.kM)
    L{end+1} = sprintf(['Step 1:  ideal %.3f N/%s,  measured k_M = %.2f  ->  the real muscle makes %.0f%% of the ' ...
                        'ideal force  (R^2 = %.3f, %d readings)'], Q.perUnit, un, Q.kM, 100*Q.kM, Q.R2, Q.n);
else
    L{end+1} = 'Step 1:  type peak pressure and load cell force for one muscle to get the correction factor k_M.';
end
if isfinite(T.tau)
    if T.rising
        s = sprintf('Step 2:  fill time constant tau = %.2f s (99%% full after %.1f s)', T.tau, 5*T.tau);
    else
        s = sprintf('Step 2:  tau = %.1f s, half-life %.1f s, %.1f%% of peak force lost in a %.1f s squeeze', ...
                    T.tau, T.half, 100*T.loss, T.tHold);
        if T.loss < 0.05
            s = [s '  ->  leak does not affect the peak load'];
        elseif T.loss >= 0.05
            s = [s '  ->  leak DOES lower the peak load'];
        end
    end
    if T.atEdge, s = [s '  (too slow to measure in this window)']; end
    L{end+1} = sprintf('%s   (R^2 = %.3f)', s, T.R2);
else
    L{end+1} = 'Step 2:  type at least 3 (time, pressure) readings to get the time constant.';
end
if R.valid
    s = sprintf('Step 3:  %.1f %s in orientation %s  ->  ideal F_M = %.1f N, F_LC = %.1f N', ...
                R.Pin, un, D.labels{D.pressOri}, R.FMideal, R.FLCideal);
    if isfinite(R.kM), s = sprintf('%s;  corrected F_M = %.1f N, F_LC = %.1f N', s, R.FMcorr, R.FLCcorr); end
    L{end+1} = s;
    if isfinite(R.P.kJ)
        L{end+1} = sprintf(['         Tab 5 jaw readings: corrected prediction off by %.0f%% on average, ' ...
                            'jaw factor k_J = %.2f  ->  expected bite force %.1f N'], R.P.errCorr, R.P.kJ, R.FLCjaw);
    else
        L{end+1} = '         Add jaw readings (pressure, load cell) for this orientation on Tab 5 to check the prediction.';
    end
else
    L{end+1} = 'Step 3:  fill in this orientation on the Jaw setup tab.';
end
A.h.cSum.Text = L;
end

function drawSim(fig)
A = fig.UserData;  i = find(strcmp(A.D.labels, A.h.ori.Value));
drawJaw(A.h.jawAx, A.D, i, A.phi, A.C);
drawTorque(A.h.torqueAx, A.D, i, A.phi, A.C);
M = computeModel(A.D);
if M.valid(i)
    K = jawKin(A.D, i, A.phi);
    A.h.readout.Text = sprintf(['   Opening %.1f deg     Muscle length %.1f mm     Muscle force %.1f N     ' ...
        'Torque %.0f N*mm     Bite force %.2f N'], A.phi, K.L, K.FM, K.tau, K.Fbite);
else
    A.h.readout.Text = '   Fill in this orientation on the Jaw setup tab.';
end
end

function pushUI(fig)
A = fig.UserData;  D = A.D;
A.h.team.Value = D.team;  A.h.mode.Value = A.h.mode.Items{D.mode};  A.h.a.Value = D.a;
A.h.sL.Value = D.sigLen;  A.h.sA.Value = D.sigArm;  A.h.sT.Value = D.sigTheta;
A.h.geom.Data = D.geom;  A.h.meas.Data = measToCell(D.meas);
A.h.pOri.Value = D.labels{D.pressOri};  A.h.pD0.Value = D.D0;  A.h.pTh0.Value = D.braid0;
A.h.pL.Value = D.Lm;  A.h.pMax.Value = D.Pmax;  A.h.pTab.Data = measToCell(D.press);
A.h.cUnit.Value = D.calUnit;  A.h.cX.Value = D.calX;  A.h.cTab.Data = measToCell(D.cal);
A.h.dMode.Value = A.h.dMode.Items{D.decayMode};  A.h.dHold.Value = D.tHold;
A.h.dTab.Data = measToCell(D.decay);  A.h.cOri.Value = D.labels{D.pressOri};  A.h.cPeak.Value = D.peakP;
setCalUnitLabels(A, D.calUnit);
refreshAll(fig);
end

function setCalUnitLabels(A, un)
A.h.cTab.ColumnName = {['Peak pressure (' un ')'], 'Load cell (N)'};
A.h.dTab.ColumnName = {'Time (s)', ['Pressure (' un ')']};
A.h.cPeakLbl.Text = sprintf('Peak pressure (%s)', un);
end

% ---------- callbacks ----------
function onSettings(fig)
A = fig.UserData;
A.D.team = A.h.team.Value;  A.D.mode = find(strcmp(A.h.mode.Items, A.h.mode.Value));
A.D.a = A.h.a.Value;  A.D.sigLen = A.h.sL.Value;  A.D.sigArm = A.h.sA.Value;  A.D.sigTheta = A.h.sT.Value;
A.D.isExample = false;
fig.UserData = A;  refreshAll(fig);
end

function onGeomEdit(fig)
A = fig.UserData;  A.D.geom = double(A.h.geom.Data);  A.D.isExample = false;
fig.UserData = A;  refreshAll(fig);
end

function onMeasEdit(fig)
A = fig.UserData;  A.D.meas = cellToMeas(A.h.meas.Data);  A.D.isExample = false;
A.h.meas.Data = measToCell(A.D.meas);
fig.UserData = A;  refreshAll(fig);
end

function onClearMeas(fig)
A = fig.UserData;
if strcmp(uiconfirm(fig, 'Clear every measured force?', 'Clear', 'Options', {'Clear', 'Cancel'}), 'Clear')
    A.D.meas = NaN(10, 5);  A.D.isExample = false;  fig.UserData = A;  pushUI(fig);
end
end

function onExample(fig)
A = fig.UserData;
if strcmp(uiconfirm(fig, 'Replace everything with the example numbers?', 'Example', ...
          'Options', {'Replace', 'Cancel'}), 'Replace')
    A.D = exampleData();  fig.UserData = A;  pushUI(fig);
end
end

function onSaveTeam(fig)
A = fig.UserData;
nm = regexprep(A.D.team, '[^\w-]', '_');
[f, p] = uiputfile('*.mat', 'Save team file', [nm '_jaw.mat']);
try, figure(fig); catch, end
if isequal(f, 0), return, end
D = A.D;  save(fullfile(p, f), 'D');
uialert(fig, sprintf('Saved %s', f), 'Saved', 'Icon', 'success');
end

function onOpenTeam(fig)
[f, p] = uigetfile('*.mat', 'Open team file');
try, figure(fig); catch, end
if isequal(f, 0), return, end
S = load(fullfile(p, f));
if ~isfield(S, 'D'), uialert(fig, 'That file is not a jaw team file.', 'Open'); return, end
A = fig.UserData;  A.D = fillDefaults(S.D);  fig.UserData = A;  pushUI(fig);
end

function onImport(fig)
[f, p] = uigetfile('*.json', 'Choose the exported leaderboard JSON');
try, figure(fig); catch, end
if isequal(f, 0), return, end
A = fig.UserData;
try
    raw = jsondecode(fileread(fullfile(p, f)));
    if isfield(raw, 'jawboard'), raw = raw.jawboard; end
    cls = matlab.lang.makeValidName(A.h.cls.Value);
    if ~isfield(raw, cls) || ~isfield(raw.(cls), 'trials')
        uialert(fig, sprintf('No results for class "%s" in that file.', A.h.cls.Value), 'Import');  return
    end
    tr = raw.(cls).trials;  ids = fieldnames(tr);
    codes = [A.D.labels, {'ALT1', 'ALT2', 'ALT3'}];
    vals = cell(10, 1);  tms = cell(10, 1);
    for k = 1:numel(ids)
        t = tr.(ids{k});
        if isfield(t, 'team') && strcmp(t.team, A.h.slot.Value)
            r = find(strcmp(codes, t.config));
            if ~isempty(r)
                vals{r}(end+1) = t.force;
                if isfield(t, 't'), tms{r}(end+1) = t.t; else, tms{r}(end+1) = k; end
            end
        end
    end
    m = NaN(10, 5);  total = 0;
    for r = 1:10
        if isempty(vals{r}), continue, end
        [~, o] = sort(tms{r}, 'descend');  v = vals{r}(o);  v = v(1:min(5, end));
        m(r, 1:numel(v)) = fliplr(v);  total = total + numel(v);
    end
    A.D.meas = m;  A.D.isExample = false;  fig.UserData = A;  pushUI(fig);
    uialert(fig, sprintf('Imported %d squeezes for %s.', total, A.h.slot.Value), 'Imported', 'Icon', 'success');
catch err
    uialert(fig, ['Could not read that file: ' err.message], 'Import');
end
end

function onPressSettings(fig)
A = fig.UserData;
A.D.pressOri = find(strcmp(A.D.labels, A.h.pOri.Value));
A.D.D0 = A.h.pD0.Value;  A.D.braid0 = A.h.pTh0.Value;  A.D.Lm = A.h.pL.Value;  A.D.Pmax = A.h.pMax.Value;
A.h.cOri.Value = A.h.pOri.Value;
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function onPressEdit(fig)
A = fig.UserData;  A.D.press = cellToMeas(A.h.pTab.Data);  A.D.isExample = false;
A.h.pTab.Data = measToCell(A.D.press);
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function onCalSettings(fig)
A = fig.UserData;
A.D.calX = A.h.cX.Value;  A.D.tHold = A.h.dHold.Value;  A.D.peakP = A.h.cPeak.Value;
A.D.decayMode = find(strcmp(A.h.dMode.Items, A.h.dMode.Value));
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function onCalUnit(fig)
% Switch psi <-> kPa and convert the numbers already typed in.
A = fig.UserData;  old = A.D.calUnit;  new = A.h.cUnit.Value;
if strcmp(old, new), return, end
f = kPaPer(old) / kPaPer(new);
A.D.cal(:,1) = A.D.cal(:,1) * f;  A.D.decay(:,2) = A.D.decay(:,2) * f;  A.D.peakP = A.D.peakP * f;
A.D.calUnit = new;
A.h.cTab.Data = measToCell(rndTable(A.D.cal));  A.h.dTab.Data = measToCell(rndTable(A.D.decay));
A.h.cPeak.Value = rnd(A.D.peakP, 3);  setCalUnitLabels(A, new);
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function m = rndTable(m)
m = round(m * 1000) / 1000;
end

function onCalEdit(fig)
A = fig.UserData;  A.D.cal = cellToMeas(A.h.cTab.Data);  A.D.isExample = false;  A.D.calIsExample = false;
A.h.cTab.Data = measToCell(A.D.cal);
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function onDecayEdit(fig)
A = fig.UserData;  A.D.decay = cellToMeas(A.h.dTab.Data);  A.D.isExample = false;  A.D.calIsExample = false;
A.h.dTab.Data = measToCell(A.D.decay);
fig.UserData = A;  drawCalTab(fig);
end

function onCalOri(fig)
A = fig.UserData;
A.D.pressOri = find(strcmp(A.D.labels, A.h.cOri.Value));  A.h.pOri.Value = A.h.cOri.Value;
fig.UserData = A;  drawPressureTab(fig);  drawCalTab(fig);
end

function onClearCal(fig)
A = fig.UserData;
if strcmp(uiconfirm(fig, 'Clear the Step 1 and Step 2 readings?', 'Clear', 'Options', {'Clear', 'Cancel'}), 'Clear')
    A.D.cal(:) = NaN;  A.D.decay(:) = NaN;  A.D.isExample = false;  A.D.calIsExample = false;
    A.h.cTab.Data = measToCell(A.D.cal);  A.h.dTab.Data = measToCell(A.D.decay);
    fig.UserData = A;  refreshAll(fig);
end
end

function onSaveCalGraphs(fig)
A = fig.UserData;
p = uigetdir(pwd, 'Choose a folder for the two graphs');
try, figure(fig); catch, end
if isequal(p, 0), return, end
exportgraphics(A.h.calAx, fullfile(p, 'pressure_calibration_step1.png'), 'Resolution', 200, 'BackgroundColor', 'white');
exportgraphics(A.h.decAx, fullfile(p, 'pressure_time_constant_step2.png'), 'Resolution', 200, 'BackgroundColor', 'white');
uialert(fig, 'Saved pressure_calibration_step1.png and pressure_time_constant_step2.png', 'Saved', 'Icon', 'success');
end

function onSyringe(fig)
A = fig.UserData;  V0 = A.h.sV0.Value;  V = A.h.sV.Value;
if V >= V0
    A.h.sOut.Text = 'Pushed-to volume must be smaller than the sealed volume.';
else
    Pk = syringePressure(V0, V);
    A.h.sOut.Text = sprintf('About %.0f kPa (%.1f psi) gauge, at most', Pk, Pk/6.895);
end
end

function onSavePressGraph(fig)
A = fig.UserData;
[f, p] = uiputfile('*.png', 'Save graph', 'force_vs_pressure.png');
try, figure(fig); catch, end
if isequal(f, 0), return, end
exportgraphics(A.h.pAx, fullfile(p, f), 'Resolution', 200, 'BackgroundColor', 'white');
uialert(fig, sprintf('Saved %s', f), 'Saved', 'Icon', 'success');
end

function onOri(fig)
A = fig.UserData;  A.phi = 0;  A.h.slider.Value = 0;  fig.UserData = A;  drawSim(fig);
end

function onSlide(fig, v)
A = fig.UserData;  A.phi = v;  fig.UserData = A;  drawSim(fig);
end

function onPlay(fig)
A = fig.UserData;
if A.playing, return, end
A.playing = true;  A.h.play.Enable = 'off';  fig.UserData = A;
for ph = 30:-1:0
    if ~isvalid(fig), return, end
    A = fig.UserData;  A.phi = ph;  A.h.slider.Value = ph;  fig.UserData = A;
    drawSim(fig);  drawnow limitrate;  pause(0.04);
end
A = fig.UserData;  A.playing = false;  A.h.play.Enable = 'on';  fig.UserData = A;
end

function onGraph(fig)
A = fig.UserData;  A.graph = find(strcmp(graphNames(), A.h.graph.Value));
fig.UserData = A;  drawGraph(A.h.resAx, A.D, computeModel(A.D), A.graph, A.C);
end

function onSaveGraph(fig)
A = fig.UserData;  nm = graphNames();
fn = [regexprep(lower(nm{A.graph}), '[^a-z0-9]+', '_') '.png'];
[f, p] = uiputfile('*.png', 'Save graph', fn);
try, figure(fig); catch, end
if isequal(f, 0), return, end
exportgraphics(A.h.resAx, fullfile(p, f), 'Resolution', 200, 'BackgroundColor', 'white');
uialert(fig, sprintf('Saved %s', f), 'Saved', 'Icon', 'success');
end

function onSaveAll(fig)
A = fig.UserData;
p = uigetdir(pwd, 'Choose a folder for the graphs and spreadsheet');
try, figure(fig); catch, end
if isequal(p, 0), return, end
M = computeModel(A.D);  nm = graphNames();
for k = 1:numel(nm)
    drawGraph(A.h.resAx, A.D, M, k, A.C);  drawnow;
    exportgraphics(A.h.resAx, fullfile(p, sprintf('%d_%s.png', k, regexprep(lower(nm{k}), '[^a-z0-9]+', '_'))), ...
                   'Resolution', 200, 'BackgroundColor', 'white');
end
drawGraph(A.h.resAx, A.D, M, A.graph, A.C);
exportgraphics(A.h.pAx, fullfile(p, sprintf('%d_force_vs_pressure.png', numel(nm) + 1)), ...
               'Resolution', 200, 'BackgroundColor', 'white');
team = regexprep(A.D.team, '[^\w-]', '_');
res = [resultsHeader(); resultsCell(A.D, M)];
geo = [{'Orientation', 'Angle theta (deg)', 'R_MX (mm)', 'R_MY (mm)', 'R_LC (mm)', 'b1 (mm)', 'b2 (mm)', 'x1 (mm)', 'x2 (mm)'}; ...
       [A.D.labels', num2cell(A.D.geom)]];
mea = [{'Orientation', 'Squeeze 1', 'Squeeze 2', 'Squeeze 3', 'Squeeze 4', 'Squeeze 5'}; ...
       [rowNames(A.D)', num2cell(A.D.meas)]];
fit = {'Least-squares muscle coefficient a (N/mm)', M.aFit; 'R squared', M.R2; 'Class value a (N/mm)', A.D.a};
xl = fullfile(p, [team '_jaw_results.xlsx']);
try
    writecell(res, xl, 'Sheet', 'Results');  writecell(geo, xl, 'Sheet', 'Jaw setup');
    writecell(mea, xl, 'Sheet', 'Measured');  writecell(fit, xl, 'Sheet', 'Muscle fit');
    pr = {'Orientation', 'Braid angle 1 (deg)', 'Braid angle 2 (deg)', 'Muscle force per kPa (N/kPa)', ...
          'Bite force per kPa (N/kPa)', 'Pressure for class-model force (kPa)'};
    for r = 1:7
        P = pressureModel(A.D, M, r);
        pr(end+1, :) = {A.D.labels{r}, rnd(P.theta(1),1), rnd(P.theta(2),1), rnd(P.slopeM,4), ...
                        rnd(P.slopeLC,4), rnd(P.Pimp,1)};  %#ok<AGROW>
    end
    pr(end+2, 1:2) = {'Diameter D0 (mm)', A.D.D0};
    pr(end+1, 1:2) = {'Relaxed braid angle (deg)', A.D.braid0};
    pr(end+1, 1:2) = {'Relaxed muscle length (mm)', A.D.Lm};
    writecell(pr, xl, 'Sheet', 'Force vs pressure');
    pd = [{sprintf('Pressure (kPa), orientation %s', A.D.labels{A.D.pressOri}), 'Load cell force (N)'}; num2cell(A.D.press)];
    writecell(pd, xl, 'Sheet', 'Pressure readings');
    writecell(calSheet(A.D, M), xl, 'Sheet', 'Pressure calibration');
    msg = sprintf('Saved %d graphs and %s_jaw_results.xlsx', numel(nm) + 1, team);
catch
    writecell(res, fullfile(p, [team '_jaw_results.csv']));
    msg = sprintf('Saved %d graphs and %s_jaw_results.csv', numel(nm) + 1, team);
end
uialert(fig, msg, 'Saved', 'Icon', 'success');
end

function S = calSheet(D, M)
% Tab 6 results as a cell array for the Excel file.
Q = calModel(D);  T = decayModel(D);  R = peakPredict(D, M, D.pressOri);  un = D.calUnit;
S = {'STEP 1: one muscle on the load cell', ''; ...
     'Pressure units', un; 'Muscle shortening during pull (mm)', D.calX; ...
     'Braid angle during pull (deg)', rnd(Q.theta, 2); ...
     sprintf('Ideal force per %s (N)', un), rnd(Q.perUnit, 4); ...
     'Correction factor k_M (measured / ideal)', rnd(Q.kM, 4); 'R squared', rnd(Q.R2, 4); ''  ''; ...
     sprintf('Peak pressure (%s)', un), 'Predicted ideal force XX (N)'};
S(end, 3:4) = {'Measured force YY (N)', 'YY / XX'};
for r = 1:Q.n
    rat = NaN;  if Q.Fi(r) > 0, rat = Q.Fm(r) / Q.Fi(r); end
    S(end+1, 1:4) = {Q.P(r), rnd(Q.Fi(r), 3), Q.Fm(r), rnd(rat, 3)};  %#ok<AGROW>
end
S(end+2, 1) = {'STEP 2: pressure time constant'};
modes = {'Leak-down (to 0)', 'Fill or settle'};
S(end+1, 1:2) = {'Curve type', modes{D.decayMode}};
S(end+1, 1:2) = {'Time constant tau (s)', rnd(T.tau, 3)};
S(end+1, 1:2) = {sprintf('A (%s)', un), rnd(T.A, 3)};
S(end+1, 1:2) = {sprintf('End pressure (%s)', un), rnd(T.Pend, 3)};
S(end+1, 1:2) = {'R squared', rnd(T.R2, 4)};
S(end+1, 1:2) = {'Half-life (s)', rnd(T.half, 3)};
S(end+1, 1:2) = {'Squeeze time (s)', D.tHold};
S(end+1, 1:2) = {'Peak force lost in one squeeze (%)', rnd(100*T.loss, 2)};
S(end+1, 1:2) = {'Time (s)', sprintf('Pressure (%s)', un)};
for r = 1:T.n, S(end+1, 1:2) = {T.t(r), T.p(r)}; end  %#ok<AGROW>
S(end+2, 1) = {sprintf('STEP 3: prediction, orientation %s', D.labels{D.pressOri})};
S(end+1, 1:2) = {sprintf('Peak pressure (%s)', un), D.peakP};
S(end+1, 1:2) = {'Ideal muscle force F_M (N)', rnd(R.FMideal, 3)};
S(end+1, 1:2) = {'Ideal bite force F_LC (N)', rnd(R.FLCideal, 3)};
S(end+1, 1:2) = {'Corrected muscle force k_M x F_M (N)', rnd(R.FMcorr, 3)};
S(end+1, 1:2) = {'Corrected bite force k_M x F_LC (N)', rnd(R.FLCcorr, 3)};
S(end+1, 1:2) = {'Jaw factor k_J (from Tab 5 readings)', rnd(R.P.kJ, 4)};
S(end+1, 1:2) = {'Expected bite force with k_M and k_J (N)', rnd(R.FLCjaw, 3)};
S(cellfun(@(c) isnumeric(c) && isscalar(c) && ~isfinite(c), S)) = {''};
for k = 1:numel(S), if isempty(S{k}), S{k} = ''; end, end
end

function onShowMath(fig)
A = fig.UserData;  C = A.C;
mf = uifigure('Name', 'Show the math', 'Position', [140 80 820 720], 'Color', 'w');
try, theme(mf, 'light'); catch, end
gm = uigridlayout(mf, [2 2]);  gm.RowHeight = {36, '1x'};  gm.ColumnWidth = {110, '1x'};  gm.BackgroundColor = 'w';
uilabel(gm, 'Text', 'Orientation', 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', C.ink);
nm = rowNames(A.D);
dd = uidropdown(gm, 'Items', nm, 'Value', A.h.ori.Value, 'FontSize', 14);
ta = uitextarea(gm, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 13, ...
                'FontColor', C.ink, 'BackgroundColor', 'w');
ta.Layout.Row = 2;  ta.Layout.Column = [1 2];
upd = @() set(ta, 'Value', mathText(fig.UserData.D, computeModel(fig.UserData.D), find(strcmp(nm, dd.Value))));
dd.ValueChangedFcn = @(s,e) upd();
upd();
end

% =========================================================================
%  SELF-TEST (no app window)
% =========================================================================

function selftest()
C = appColors();  D = exampleData();  M = computeModel(D);
fprintf('Orientation  F_M(N)  tau(N*mm)  F_LC(N)  +/-sig  meas   %%err  best theta\n');
for r = 1:7
    fprintf('%-11s %7.2f %9.1f %8.2f %7.2f %6.2f %6.1f %8.1f\n', D.labels{r}, M.FM(r), M.tau(r), ...
            M.F(r), M.sigF(r), M.measMean(r), M.pctErr(r), M.thetaBest(r));
end
fprintf('Least squares: a_fit = %.3f N/mm, R^2 = %.3f\n', M.aFit, M.R2);
K = jawKin(D, 1, 0);
fprintf('Check: kinematics torque at phi=0 %.3f vs model %.3f\n', K.tau, M.tau(1));
L = mathText(D, M, 1);  fprintf('%s\n', L{:});
L = mathText(D, M, 9);  fprintf('%s\n', L{:});
f = figure('Visible', 'off', 'Position', [0 0 1100 560], 'Color', 'w');
for k = 1:6
    clf(f);  ax = axes('Parent', f);  drawGraph(ax, D, M, k, C);
    print(f, '-dpng', '-r90', sprintf('selftest_graph%d.png', k));
end
clf(f);  ax1 = axes('Parent', f, 'Position', [0.02 0.05 0.55 0.88]);
ax2 = axes('Parent', f, 'Position', [0.64 0.14 0.33 0.75]);
drawJaw(ax1, D, 1, 0, C);  drawTorque(ax2, D, 1, 0, C);
print(f, '-dpng', '-r90', 'selftest_jaw0.png');
clf(f);  ax1 = axes('Parent', f, 'Position', [0.02 0.05 0.55 0.88]);
ax2 = axes('Parent', f, 'Position', [0.64 0.14 0.33 0.75]);
drawJaw(ax1, D, 4, 20, C);  drawTorque(ax2, D, 4, 20, C);
print(f, '-dpng', '-r90', 'selftest_jaw20.png');
P = pressureModel(D, M, 6);
fprintf('Pressure model F: %.4f N/kPa muscle, %.4f N/kPa bite, implied %.0f kPa\n', P.slopeM, P.slopeLC, P.Pimp);
for md = 1:2
    clf(f);  ax = axes('Parent', f);  drawPressure(ax, D, P, md, C);
    print(f, '-dpng', '-r90', sprintf('selftest_pressure%d.png', md));
end
L = mathText(D, M, 6);  fprintf('%s\n', L{:});
% Tab 6: pressure calibration, time constant and prediction
Q = calModel(D);  T = decayModel(D);
fprintf('Calibration: theta %.2f deg, ideal %.4f N/%s, k_M = %.4f, R^2 = %.4f\n', Q.theta, Q.perUnit, D.calUnit, Q.kM, Q.R2);
fprintf('Time constant: tau = %.3f s, R^2 = %.4f, loss in %.1f s = %.2f%%\n', T.tau, T.R2, T.tHold, 100*T.loss);
% exact data must give back the tau it was made with
Dt = D;  tt = (0:1:15)';
Dt.decay = NaN(16, 2);  Dt.decay(:,1) = tt;  Dt.decay(:,2) = 20*exp(-tt/7.5);  Dt.decayMode = 1;
T1 = decayModel(Dt);
Dt.decay(:,2) = 30 - 25*exp(-tt/2.2);  Dt.decayMode = 2;
T2 = decayModel(Dt);
fprintf('Recover tau: leak 7.5 -> %.4f s, fill 2.2 -> %.4f s (P_end %.3f, rising %d)\n', T1.tau, T2.tau, T2.Pend, T2.rising);
assert(abs(T1.tau - 7.5) < 1e-3 && abs(T2.tau - 2.2) < 1e-3 && abs(T2.Pend - 30) < 1e-3);
% calibration with exact data must give back the factor
Dc = D;  Dc.cal = NaN(8, 2);  Dc.cal(1:4, 1) = [5; 10; 15; 20];
Dc.cal(1:4, 2) = 0.6 * calModel(D).perUnit * Dc.cal(1:4, 1);
assert(abs(calModel(Dc).kM - 0.6) < 1e-9);
% psi and kPa must give the same answers
Dk = D;  Dk.calUnit = 'kPa';  fk = kPaPer('psi');
Dk.cal(:,1) = D.cal(:,1)*fk;  Dk.decay(:,2) = D.decay(:,2)*fk;  Dk.peakP = D.peakP*fk;
assert(abs(calModel(Dk).kM - Q.kM) < 1e-9 && abs(decayModel(Dk).tau - T.tau) < 1e-3);
assert(abs(peakPredict(Dk, M, 6).FLCcorr - peakPredict(D, M, 6).FLCcorr) < 1e-9);
% jaw readings made from k_M x k_J x theory must give back k_J
Dj = D;  Pj = pressureModel(D, M, 6);  Dj.pressOri = 6;
Dj.press = NaN(8, 2);  Dj.press(1:3, 1) = [60; 100; 140];
Dj.press(1:3, 2) = Q.kM * 0.8 * Pj.slopeLC * Dj.press(1:3, 1);
Pj = pressureModel(Dj, M, 6);
fprintf('Jaw factor from synthetic readings: k_J = %.4f (expect 0.8000), error %.2e%%\n', Pj.kJ, Pj.errCorr);
assert(abs(Pj.kJ - 0.8) < 1e-9);
S = calSheet(Dj, M);  fprintf('Excel sheet: %d x %d cells\n', size(S, 1), size(S, 2));
Lc = calMathText(Dj, M, 6);  fprintf('%s\n', Lc{:});
clf(f);  ax = axes('Parent', f);  drawCal(ax, D, Q, C);   print(f, '-dpng', '-r90', 'selftest_cal1.png');
clf(f);  ax = axes('Parent', f);  drawDecay(ax, D, T, C); print(f, '-dpng', '-r90', 'selftest_cal2.png');
clf(f);  ax = axes('Parent', f);  drawDecay(ax, Dt, T2, C); print(f, '-dpng', '-r90', 'selftest_cal3.png');
clf(f);  ax = axes('Parent', f);  drawPressure(ax, Dj, pressureModel(Dj, M, 6), 2, C);
print(f, '-dpng', '-r90', 'selftest_pressure3.png');
E = fillDefaults(rmfield(D, {'cal', 'decay', 'calUnit', 'calIsExample'}));
assert(all(isnan(E.cal(:))) && strcmp(E.calUnit, 'psi') && ~E.calIsExample);
close(f);
fprintf('Self-test finished.\n');
end