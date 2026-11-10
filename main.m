
clear;
clc;
close all;


projectFolder = fileparts(mfilename('fullpath'));
if isempty(projectFolder)
    projectFolder = pwd;  %missing folders are created automatically
end
inputFolder   = fullfile(projectFolder, 'TestImages');
outputFolder  = fullfile(projectFolder, 'Results');
conceptFolder = fullfile(outputFolder, 'A_Concepts');
caseFolder    = fullfile(outputFolder, 'B_TestCases');
if ~exist(conceptFolder, 'dir'), mkdir(conceptFolder); end
if ~exist(caseFolder, 'dir'),    mkdir(caseFolder);    end

rng(1);                     % same random noise on every run
IMAGE_SIZE = 256;           % every image is resized to 256 x 256

DC_RADIUS         = 12;     
BACKGROUND_WINDOW = 15;      %used to smoothen the surface using medfilt->finds residue
PEAK_THRESHOLD    = 6;     
MIN_RADIUS        = 2;     
MAX_RADIUS        = 8;     
FIXED_NOISE  = [20 0];
FIXED_RADIUS = 5;

%Random-noise detectors
IMPULSE_LIMIT = 0.005;      %salt and pepper (if more than 0.5% of the pixels are black and white)
GAUSS_LIMIT   = 0.030;      % if estimated graininess>0.03 gaussian
SPECKLE_RATIO = 1.6;        % noise in bright areas > 1.6 x noise in dark areas -> speckle
MEDIAN_SMAX   = 7;          % largest window of the adaptive median filter
LOCAL_WINDOW  = 5;        9  % window of the adaptive local noise reduction filter
NOISE_FACTOR  = 1.5;        % safety factor on the estimated noise variance


tc = struct('file', {}, 'periodic', {}, 'gaussVar', {}, 'spDens', {}, 'speckVar', {});
tc(1)  = makeCase('cameraman.tif',                       [20 0 0.15],              0,     0,    0);
tc(2)  = makeCase(fullfile(inputFolder,'image02.png'),   [],                       0.010, 0,    0);
tc(3)  = makeCase('coins.png',                           [],                       0,     0.05, 0);
tc(4)  = makeCase('peppers.png',                         [0 30 0.12; 25 25 0.10],  0,     0,    0);
tc(5)  = makeCase(fullfile(inputFolder,'image05.png'),   [],                       0,     0,    0.04);
tc(6)  = makeCase(fullfile(inputFolder,'image07.png'),   [35 -20 0.15],            0,     0.10, 0);
tc(7)  = makeCase('pout.tif',                            [],                       0.005, 0.02, 0);
tc(8)  = makeCase('football.jpg',                        [40 15 0.12],             0.010, 0,    0);
tc(9)  = makeCase(fullfile(inputFolder,'image10.png'), ...
                  [12 18 .08; -40 22 .08; 70 -35 .08; 5 55 .06; 95 10 .06],         0.003, 0,    0);
tc(10) = makeCase('onion.png',                           [60 60 0.12; 15 -45 0.10], 0.005, 0.03, 0);

% Safety net: a missing file is replaced by a spare toolbox image.
backupImages = {'rice.png', 'tire.tif', 'pears.png', 'kids.tif'};
nextBackup = 1;
for k = 1:numel(tc)
    if exist(tc(k).file, 'file') == 0
        fprintf('Note: %s not found -> using %s instead.\n', tc(k).file, backupImages{nextBackup});
        tc(k).file = backupImages{nextBackup};
        nextBackup = nextBackup + 1;
    end
end
NUM_CASES = numel(tc);

fprintf('\n==========================================================\n');
fprintf(' ADAPTIVE IMAGE RESTORATION SYSTEM\n');
fprintf(' Adaptive notch (periodic) + adaptive spatial filters (random)\n');
fprintf('==========================================================\n\n');


fprintf('PART A: concept demonstrations ...\n');

grayDemo  = loadImage('cameraman.tif', IMAGE_SIZE, true);
coinsDemo = loadImage('coins.png',     IMAGE_SIZE, true);
colorDemo = loadImage('peppers.png',   IMAGE_SIZE, false);


R = colorDemo(:,:,1);  G = colorDemo(:,:,2);  B = colorDemo(:,:,3);
CMY = 1 - colorDemo;                      % subtractive model: C = 1-R, M = 1-G, Y = 1-B
HSV = rgb2hsv(colorDemo);                 % hue, saturation, value
YCC = rgb2ycbcr(colorDemo);               % luminance Y, chroma Cb, Cr
grayFromColor = rgb2gray(colorDemo);      % 0.299R + 0.587G + 0.114B

fig = newFigure([50 50 1400 800]);
subplot(3,5,1);  imshow(colorDemo);      title('RGB image');
subplot(3,5,2);  imshow(R);              title('R channel');
subplot(3,5,3);  imshow(G);              title('G channel');
subplot(3,5,4);  imshow(B);              title('B channel');
subplot(3,5,5);  imshow(grayFromColor);  title('Gray = 0.299R+0.587G+0.114B');
subplot(3,5,6);  imshow(CMY);            title('CMY = 1 - RGB');
subplot(3,5,7);  imshow(CMY(:,:,1));     title('C channel');
subplot(3,5,8);  imshow(CMY(:,:,2));     title('M channel');
subplot(3,5,9);  imshow(CMY(:,:,3));     title('Y channel');
subplot(3,5,10); imshow(HSV(:,:,1));     title('HSV: Hue');
subplot(3,5,11); imshow(HSV(:,:,2));     title('HSV: Saturation');
subplot(3,5,12); imshow(HSV(:,:,3));     title('HSV: Value');
subplot(3,5,13); imshow(YCC(:,:,1));     title('YCbCr: Y (luminance)');
subplot(3,5,14); imshow(YCC(:,:,2));     title('YCbCr: Cb');
subplot(3,5,15); imshow(YCC(:,:,3));     title('YCbCr: Cr');
saveFigure(fig, fullfile(conceptFolder, 'A1_colour_models.png'));

% ---------- A2. Intensity transformations ----------
c = 2;                                          % scale factor
logImg    = mat2gray(c * log(1 + 255*grayDemo));  % dynamic range compression (r on 0..255 scale)
sliceLow  = 0.35;  sliceHigh = 0.65;            % gray levels to highlight
sliced    = grayDemo;
sliced(grayDemo >= sliceLow & grayDemo <= sliceHigh) = 1;   % background preserved
gray8     = im2uint8(grayDemo);
histEq    = histeq(grayDemo);

fig = newFigure([50 50 1400 800]);
subplot(3,4,1); imshow(grayDemo);  title('Original');
subplot(3,4,2); imshow(logImg);    title('Log transform  s = c log(1+r)');
subplot(3,4,3); imshow(sliced);    title('Intensity slicing [0.35, 0.65]');
subplot(3,4,4); imshow(histEq);    title('Histogram equalised');
subplot(3,4,5); imhist(grayDemo);  title('Histogram: original');
subplot(3,4,6); imhist(histEq);    title('Histogram: equalised');
for b = 1:6
    % bit planes 8 (most significant) down to 3
    plane = 9 - b;
    subplot(3,4,6 + b);
    imshow(double(bitget(gray8, plane)));
    title(sprintf('Bit plane %d', plane));
end
saveFigure(fig, fullfile(conceptFolder, 'A2_intensity_transforms.png'));

fig = newFigure([50 50 1200 600]);
for plane = 1:8
    subplot(2,4,plane);
    imshow(double(bitget(gray8, plane)));
    title(sprintf('Bit plane %d', plane));
end
saveFigure(fig, fullfile(conceptFolder, 'A2_all_bit_planes.png'));

% ---------- A3. Noise models ----------
noiseGauss = imnoise(grayDemo, 'gaussian', 0, 0.005);
noiseSP    = imnoise(grayDemo, 'salt & pepper', 0.05);
noiseSpeck = imnoise(grayDemo, 'speckle', 0.04);
noisePer   = min(max(grayDemo + makePeriodicNoise(IMAGE_SIZE, [20 0 0.15]), 0), 1);

flat = 0.5 * ones(IMAGE_SIZE);                  % flat gray patch shows the noise PDF
fig = newFigure([50 50 1400 650]);
subplot(2,4,1); imshow(noiseGauss); title('Gaussian (var 0.005)');
subplot(2,4,2); imshow(noiseSP);    title('Salt & pepper (0.05)');
subplot(2,4,3); imshow(noiseSpeck); title('Speckle (var 0.04)');
subplot(2,4,4); imshow(noisePer);   title('Periodic (sinusoidal)');
subplot(2,4,5); imhist(imnoise(flat, 'gaussian', 0, 0.005));   title('Gaussian PDF');
subplot(2,4,6); imhist(imnoise(flat, 'salt & pepper', 0.05));  title('Impulse PDF');
subplot(2,4,7); imhist(imnoise(flat, 'speckle', 0.04));        title('Speckle PDF');
subplot(2,4,8); imshow(log(1 + abs(fftshift(fft2(noisePer)))), []);
title('Periodic: spikes in spectrum');
saveFigure(fig, fullfile(conceptFolder, 'A3_noise_models.png'));

% ---------- A4. Spatial smoothing filters ----------
meanManual  = arithmeticMean3x3(noiseGauss);                   % manual formula
box9        = imfilter(noiseGauss, ones(9)/81, 'replicate');   % 9x9 average box
w           = [1 2 3 4 5 4 3 2 1];
weighted9   = imfilter(noiseGauss, (w' * w) / sum(w)^2, 'replicate');
median3     = medfilt2(noiseSP, [3 3], 'symmetric');
pepperOnly  = grayDemo;  pepperOnly(rand(size(grayDemo)) < 0.05) = 0;   % black dots only
saltOnly    = grayDemo;  saltOnly(rand(size(grayDemo)) < 0.05)   = 1;   % white dots only
maxF        = ordfilt2(pepperOnly, 9, ones(3), 'symmetric');   % max filter removes pepper
minF        = ordfilt2(saltOnly,   1, ones(3), 'symmetric');   % min filter removes salt
midF        = (ordfilt2(noiseGauss, 9, ones(3), 'symmetric') + ...
               ordfilt2(noiseGauss, 1, ones(3), 'symmetric')) / 2;   % midpoint (Gaussian)
alphaF      = alphaTrimmedMean(noiseSP, 3, 4);                 % drop 2 lowest + 2 highest
adaptMed    = adaptiveMedian(noiseSP, MEDIAN_SMAX);
adaptLocal  = adaptiveLocalFilter(noiseGauss, 0.005, LOCAL_WINDOW);

fig = newFigure([50 50 1500 800]);
subplot(3,5,1);  imshow(noiseGauss); title(sprintf('Gaussian noisy %.1f dB', psnr(noiseGauss, grayDemo)));
subplot(3,5,2);  imshow(meanManual); title(sprintf('3x3 mean (manual) %.1f dB', psnr(meanManual, grayDemo)));
subplot(3,5,3);  imshow(box9);       title(sprintf('9x9 box %.1f dB', psnr(box9, grayDemo)));
subplot(3,5,4);  imshow(weighted9);  title(sprintf('9x9 weighted %.1f dB', psnr(weighted9, grayDemo)));
subplot(3,5,5);  imshow(adaptLocal); title(sprintf('Adaptive local %.1f dB', psnr(adaptLocal, grayDemo)));
subplot(3,5,6);  imshow(noiseSP);    title(sprintf('S&P noisy %.1f dB', psnr(noiseSP, grayDemo)));
subplot(3,5,7);  imshow(median3);    title(sprintf('3x3 median %.1f dB', psnr(median3, grayDemo)));
subplot(3,5,8);  imshow(maxF);       title(sprintf('Max on pepper %.1f dB', psnr(maxF, grayDemo)));
subplot(3,5,9);  imshow(minF);       title(sprintf('Min on salt %.1f dB', psnr(minF, grayDemo)));
subplot(3,5,10); imshow(midF);       title(sprintf('Midpoint on Gaussian %.1f dB', psnr(midF, grayDemo)));
subplot(3,5,11); imshow(alphaF);     title(sprintf('Alpha-trimmed %.1f dB', psnr(alphaF, grayDemo)));
subplot(3,5,12); imshow(adaptMed);   title(sprintf('Adaptive median %.1f dB', psnr(adaptMed, grayDemo)));
subplot(3,5,13); imshow(imfilter(noiseSP, ones(9)/81, 'replicate'));
title(sprintf('9x9 box on S&P %.1f dB', psnr(imfilter(noiseSP, ones(9)/81, 'replicate'), grayDemo)));
homoF = homomorphicFilter(noiseSpeck, NOISE_FACTOR, LOCAL_WINDOW);
subplot(3,5,14); imshow(noiseSpeck); title(sprintf('Speckle noisy %.1f dB', psnr(noiseSpeck, grayDemo)));
subplot(3,5,15); imshow(homoF);      title(sprintf('Log + adaptive + exp %.1f dB', psnr(homoF, grayDemo)));
saveFigure(fig, fullfile(conceptFolder, 'A4_smoothing_filters.png'));

% ---------- A5. Edge detection and Laplacian sharpening ----------
coinsSP   = imnoise(coinsDemo, 'salt & pepper', 0.02);
coinsMed  = medfilt2(coinsSP, [3 3], 'symmetric');
coinsBox  = imfilter(coinsSP, ones(9)/81, 'replicate');
coinsMed5 = medfilt2(coinsSP, [5 5], 'symmetric');
srcs  = {coinsSP, coinsBox, coinsMed, coinsMed5};
names = {'Noisy', '9x9 box', '3x3 median', '5x5 median'};
ops   = {'roberts', 'prewitt', 'sobel'};
fig = newFigure([50 50 1400 900]);
for r = 1:4
    subplot(4,4,(r-1)*4 + 1); imshow(srcs{r}); title(names{r});
    for o = 1:3
        subplot(4,4,(r-1)*4 + 1 + o);
        imshow(edge(srcs{r}, ops{o}));
        title(sprintf('%s: %s', names{r}, ops{o}));
    end
end
saveFigure(fig, fullfile(conceptFolder, 'A5_edge_detection.png'));

lap4 = [0 1 0; 1 -4 1; 0 1 0];                  % 4-neighbourhood
lap8 = [1 1 1; 1 -8 1; 1 1 1];                  % 8-neighbourhood
L4 = imfilter(coinsDemo, lap4, 'replicate');
L8 = imfilter(coinsDemo, lap8, 'replicate');
sharp4 = min(max(coinsDemo - L4, 0), 1);        % g = f - Laplacian (centre is negative)
sharp8 = min(max(coinsDemo - L8, 0), 1);
fig = newFigure([50 50 1300 600]);
subplot(2,3,1); imshow(coinsDemo);  title('Original');
subplot(2,3,2); imshow(L4, []);     title('Laplacian, 4-neighbourhood');
subplot(2,3,3); imshow(L8, []);     title('Laplacian, 8-neighbourhood');
subplot(2,3,5); imshow(sharp4);     title('Sharpened (4-neighbourhood)');
subplot(2,3,6); imshow(sharp8);     title('Sharpened (8-neighbourhood)');
saveFigure(fig, fullfile(conceptFolder, 'A5_laplacian_sharpening.png'));

% ---------- A6. Morphological processing and algorithms ----------
se      = strel('disk', 3, 0);
bw      = coinsDemo > graythresh(coinsDemo);      % Otsu threshold -> binary
eroded  = imerode(bw, se);
dilated = imdilate(bw, se);
opened  = imopen(bw, se);                         % erosion then dilation
closed  = imclose(bw, se);                        % dilation then erosion
filled  = imfill(bw, 'holes');                    % hole filling
boundary = filled & ~imerode(filled, strel('square', 3));   % A - (A erode B)
[~, nObj] = bwlabel(bwareaopen(filled, 50), 8);   % connected components
topHat  = imtophat(coinsDemo, strel('disk', 15, 0)); % bright details smaller than SE

fig = newFigure([50 50 1400 650]);
subplot(2,5,1);  imshow(bw);       title('Binary (Otsu)');
subplot(2,5,2);  imshow(eroded);   title('Erosion');
subplot(2,5,3);  imshow(dilated);  title('Dilation');
subplot(2,5,4);  imshow(opened);   title('Opening');
subplot(2,5,5);  imshow(closed);   title('Closing');
subplot(2,5,6);  imshow(filled);   title('Hole filling');
subplot(2,5,7);  imshow(boundary); title('Boundary extraction');
subplot(2,5,8);  imshow(label2rgb(bwlabel(bwareaopen(filled, 50), 8)));
title(sprintf('Connected components: %d', nObj));
subplot(2,5,9);  imshow(topHat, []); title('Top-hat transform');
subplot(2,5,10); imshow(imsubtract(imdilate(coinsDemo, se), imerode(coinsDemo, se)), []);
title('Morphological gradient');
saveFigure(fig, fullfile(conceptFolder, 'A6_morphology.png'));

fprintf('   saved in %s\n\n', conceptFolder);

%% PART B : ADAPTIVE RESTORATION 
fprintf('PART B: adaptive restoration of %d test cases\n\n', NUM_CASES);

% Results: [noisyPSNR fixedPSNR meanPSNR medianPSNR adaptivePSNR
%           noisySSIM fixedSSIM meanSSIM medianSSIM adaptiveSSIM
%           notches  sigmaEstimate  impulseFraction  objectsClean objectsNoisy objectsRestored]
summary   = zeros(NUM_CASES, 16);
trueTypes = cell(NUM_CASES, 1);
detTypes  = cell(NUM_CASES, 1);
imageNames = cell(NUM_CASES, 1);

for k = 1:NUM_CASES

    %% 1. Read the clean image (gray or colour)
    clean = loadImage(tc(k).file, IMAGE_SIZE, false);
    [~, nm, ext] = fileparts(tc(k).file);
    imageNames{k} = [nm ext];
    nCh = size(clean, 3);

    %% 2. Add the noise of this case
    %   order: periodic interference -> Gaussian/speckle -> salt & pepper
    noisy = clean + repmat(makePeriodicNoise(IMAGE_SIZE, tc(k).periodic), [1 1 nCh]);
    noisy = min(max(noisy, 0), 1);
    if tc(k).gaussVar > 0, noisy = imnoise(noisy, 'gaussian', 0, tc(k).gaussVar); end
    if tc(k).speckVar > 0, noisy = imnoise(noisy, 'speckle', tc(k).speckVar);     end
    if tc(k).spDens   > 0, noisy = imnoise(noisy, 'salt & pepper', tc(k).spDens); end
    trueTypes{k} = noiseLabel(~isempty(tc(k).periodic), tc(k).gaussVar > 0, ...
                              tc(k).speckVar > 0, tc(k).spDens > 0);

    %% 3. ADAPTIVE RESTORATION (the program decides everything itself)
    % Stage 1: impulse (salt & pepper) noise -> adaptive median, per channel
    impulseFrac = 0;
    stage1 = noisy;
    for ch = 1:nCh
        f = impulseFraction(noisy(:,:,ch));
        impulseFrac = max(impulseFrac, f);
        if f > IMPULSE_LIMIT
            stage1(:,:,ch) = adaptiveMedian(noisy(:,:,ch), MEDIAN_SMAX);
        end
    end
    hasImpulse = impulseFrac > IMPULSE_LIMIT;

    % Stage 2: periodic noise -> adaptive notch, detected on the luminance
    lum1     = toGray(stage1);
    F        = fftshift(fft2(lum1));
    spectrum = log(1 + abs(F));
    [centres, radii] = detectNoiseSpikes(spectrum, DC_RADIUS, BACKGROUND_WINDOW, ...
                                         PEAK_THRESHOLD, MIN_RADIUS, MAX_RADIUS);
    H = buildNotchFilter(IMAGE_SIZE, centres, radii);
    hasPeriodic = ~isempty(centres);
    stage2 = stage1;
    if hasPeriodic
        for ch = 1:nCh
            stage2(:,:,ch) = applyMask(stage1(:,:,ch), H);
        end
    end

    % Stage 3: Gaussian / speckle noise -> adaptive local filter, per channel
    sigmaEst = 0;
    for ch = 1:nCh
        sigmaEst = max(sigmaEst, estimateNoiseSigma(stage2(:,:,ch)));
    end
    hasRandom  = sigmaEst > GAUSS_LIMIT;
    hasSpeckle = hasRandom && speckleRatio(toGray(stage2)) > SPECKLE_RATIO;
    hasGauss   = hasRandom && ~hasSpeckle;
    stage3 = stage2;
    for ch = 1:nCh
        if hasGauss
            s = estimateNoiseSigma(stage2(:,:,ch));
            stage3(:,:,ch) = adaptiveLocalFilter(stage2(:,:,ch), NOISE_FACTOR * s^2, LOCAL_WINDOW);
        elseif hasSpeckle
            stage3(:,:,ch) = homomorphicFilter(stage2(:,:,ch), NOISE_FACTOR, LOCAL_WINDOW);
        end
    end
    adaptiveOut = min(max(stage3, 0), 1);
    detTypes{k} = noiseLabel(hasPeriodic, hasGauss, hasSpeckle, hasImpulse);

    %% 4. NON-ADAPTIVE comparison filters (same for every image)
    [fc, fr] = fixedNotchPositions(IMAGE_SIZE, FIXED_NOISE, FIXED_RADIUS);
    Hfixed   = buildNotchFilter(IMAGE_SIZE, fc, fr);
    fixedOut = zeros(size(noisy));  meanOut = fixedOut;  medianOut = fixedOut;
    for ch = 1:nCh
        fixedOut(:,:,ch)  = applyMask(noisy(:,:,ch), Hfixed);
        meanOut(:,:,ch)   = imfilter(noisy(:,:,ch), ones(5)/25, 'replicate');
        medianOut(:,:,ch) = medfilt2(noisy(:,:,ch), [3 3], 'symmetric');
    end
    fixedOut = min(max(fixedOut, 0), 1);

    %% 5. Quality measures (PSNR on all channels, SSIM on luminance)
    outs = {noisy, fixedOut, meanOut, medianOut, adaptiveOut};
    for m = 1:5
        summary(k, m)     = psnr(outs{m}, clean);
        summary(k, 5 + m) = ssim(toGray(outs{m}), toGray(clean));
    end

    %% 6. Morphology check: count objects (Otsu -> opening -> fill -> label)
    summary(k, 11:16) = [size(centres,1), sigmaEst, impulseFrac, ...
                         countObjects(toGray(clean)), countObjects(toGray(noisy)), ...
                         countObjects(toGray(adaptiveOut))];

    %% 7. Save images
    imwrite(noisy,       fullfile(caseFolder, sprintf('noisy_%02d.png', k)));
    imwrite(adaptiveOut, fullfile(caseFolder, sprintf('restored_%02d.png', k)));

    %% 8. Figure 1: result comparison
    fig = newFigure([30 30 1500 700]);
    subplot(2,4,1); imshow(clean); title(['Original: ' imageNames{k}], 'Interpreter', 'none');
    subplot(2,4,2); imshow(noisy); title(sprintf('Noisy %.2f dB\nTrue: %s', summary(k,1), trueTypes{k}));
    subplot(2,4,3); imshow(spectrum, []); hold on;
    if hasPeriodic
        plot(centres(:,1), centres(:,2), 'ro', 'MarkerSize', 10, 'LineWidth', 1.2);
    end
    title(sprintf('Spectrum: %d peaks found', size(centres,1)));
    subplot(2,4,4); imshow(H); title('Adaptive notch filter H');
    subplot(2,4,5); imshow(adaptiveOut);
    title(sprintf('ADAPTIVE %.2f dB\nDetected: %s', summary(k,5), detTypes{k}));
    subplot(2,4,6); imshow(fixedOut);  title(sprintf('Fixed notch %.2f dB', summary(k,2)));
    subplot(2,4,7); imshow(meanOut);   title(sprintf('5x5 mean %.2f dB', summary(k,3)));
    subplot(2,4,8); imshow(medianOut); title(sprintf('3x3 median %.2f dB', summary(k,4)));
    saveFigure(fig, fullfile(caseFolder, sprintf('TestCase_%02d.png', k)), k == NUM_CASES);

    %% 9. Figure 2: the adaptive stages one by one
    fig = newFigure([30 30 1500 420]);
    subplot(1,4,1); imshow(noisy);  title('Noisy input');
    subplot(1,4,2); imshow(stage1); title(onOff('Stage 1: adaptive median', hasImpulse));
    subplot(1,4,3); imshow(min(max(stage2,0),1)); title(onOff('Stage 2: adaptive notch', hasPeriodic));
    subplot(1,4,4); imshow(adaptiveOut); title(onOff('Stage 3: adaptive local filter', hasRandom));
    saveFigure(fig, fullfile(caseFolder, sprintf('TestCase_%02d_stages.png', k)));

    %% Print result
    fprintf('Case %02d %-15s true: %-28s detected: %-28s %s\n', k, imageNames{k}, ...
            trueTypes{k}, detTypes{k}, tick(strcmp(trueTypes{k}, detTypes{k})));
    fprintf('        PSNR noisy %5.2f | fixed %5.2f | mean %5.2f | median %5.2f | ADAPTIVE %5.2f dB   SSIM %.3f -> %.3f\n', ...
            summary(k,1:5), summary(k,6), summary(k,10));
end

%% ================= SAVE SUMMARY =================
fid = fopen(fullfile(outputFolder, 'summary.csv'), 'w');
fprintf(fid, ['Case,Image,TrueNoise,DetectedNoise,Correct,Notches,SigmaEstimate,ImpulseFraction,' ...
              'NoisyPSNR,FixedPSNR,MeanPSNR,MedianPSNR,AdaptivePSNR,' ...
              'NoisySSIM,FixedSSIM,MeanSSIM,MedianSSIM,AdaptiveSSIM,' ...
              'ObjectsClean,ObjectsNoisy,ObjectsRestored\n']);
for k = 1:NUM_CASES
    fprintf(fid, '%d,%s,%s,%s,%d,%d,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d\n', ...
        k, imageNames{k}, trueTypes{k}, detTypes{k}, strcmp(trueTypes{k}, detTypes{k}), ...
        summary(k,11), summary(k,12), summary(k,13), summary(k,1:10), summary(k,14:16));
end
fclose(fid);

%% ================= SUMMARY FIGURES =================
fig = newFigure([100 100 1000 450]);
bar(summary(:, 1:5));
grid on; xlabel('Test case'); ylabel('PSNR (dB)');
title('Restoration of 10 images with periodic and random noise');
legend('Noisy', 'Fixed notch', '5x5 mean', '3x3 median', 'Adaptive', 'Location', 'northwest');
saveFigure(fig, fullfile(outputFolder, 'PSNR_comparison.png'));

fig = newFigure([100 100 1000 450]);
bar(summary(:, 6:10));
grid on; xlabel('Test case'); ylabel('SSIM');
title('Structural similarity after restoration');
legend('Noisy', 'Fixed notch', '5x5 mean', '3x3 median', 'Adaptive', 'Location', 'northwest');
saveFigure(fig, fullfile(outputFolder, 'SSIM_comparison.png'));

correct = sum(strcmp(trueTypes, detTypes));
fprintf('\nNoise type detected correctly in %d of %d cases\n', correct, NUM_CASES);
fprintf('Average PSNR  noisy %.2f | fixed %.2f | mean %.2f | median %.2f | ADAPTIVE %.2f dB\n', mean(summary(:,1:5)));
fprintf('Average SSIM  noisy %.3f | fixed %.3f | mean %.3f | median %.3f | ADAPTIVE %.3f\n', mean(summary(:,6:10)));
fprintf('All results saved in: %s\n', outputFolder);


%% ==========================================================
%%                     LOCAL FUNCTIONS
%% ==========================================================

function c = makeCase(file, periodic, gaussVar, spDens, speckVar)
% Bundles one test case into a struct.
    c = struct('file', file, 'periodic', periodic, 'gaussVar', gaussVar, ...
               'spDens', spDens, 'speckVar', speckVar);
end


function img = loadImage(file, N, forceGray)
% Reads an image, scales it to 0...1 and resizes it to N x N.
% Colour images stay colour unless forceGray is true.
    img = imread(file);
    if size(img, 3) == 3 && forceGray
        img = rgb2gray(img);
    end
    img = im2double(img);
    img = imresize(img, [N N]);
    img = min(max(img, 0), 1);
end


function g = toGray(img)
% Luminance of an image (same weights as Y in YCbCr).
    if size(img, 3) == 3
        g = rgb2gray(img);
    else
        g = img;
    end
end


function noise = makePeriodicNoise(N, components)
% Sum of 2-D sinusoids. Each row of components is [u v amplitude].
    [x, y] = meshgrid(0:N-1, 0:N-1);
    noise = zeros(N, N);
    for i = 1:size(components, 1)
        noise = noise + components(i,3) * ...
                sin(2*pi*(components(i,1)*x/N + components(i,2)*y/N));
    end
end


function label = noiseLabel(periodic, gauss, speckle, impulse)
% Text label such as 'Periodic + Gaussian'.
    parts = {};
    if periodic, parts{end+1} = 'Periodic';       end
    if gauss,    parts{end+1} = 'Gaussian';       end
    if speckle,  parts{end+1} = 'Speckle';        end
    if impulse,  parts{end+1} = 'Salt&Pepper';    end
    if isempty(parts)
        label = 'None';
    else
        label = strjoin(parts, ' + ');
    end
end


function s = onOff(text, used)
    if used
        s = [text ' (applied)'];
    else
        s = [text ' (skipped)'];
    end
end


function s = tick(ok)
    if ok, s = 'OK'; else, s = 'MISMATCH'; end
end


% ---------------- Detectors ----------------

function f = impulseFraction(g)
% Fraction of pixels that look like salt & pepper: an extreme value
% (near 0 or 1) that is very different from its 3x3 median.
    med = medfilt2(g, [3 3], 'symmetric');
    isExtreme = (g <= 0.02) | (g >= 0.98);
    isOdd     = abs(g - med) > 0.4;
    f = mean(isExtreme(:) & isOdd(:));
end


function s = estimateNoiseSigma(g)
% Fast noise-sigma estimate (Immerkaer 1996). The kernel is the
% difference of two Laplacians, so smooth image content cancels out
% and mostly the random noise is left.
    M = [1 -2 1; -2 4 -2; 1 -2 1];
    [h, w] = size(g);
    r = conv2(g, M, 'valid');
    s = sqrt(pi/2) * sum(abs(r(:))) / (6 * (w-2) * (h-2));
end


function q = speckleRatio(g)
% Speckle is MULTIPLICATIVE: it is stronger in bright areas than in dark
% ones. Gaussian noise is the same everywhere. Compare the noise level in
% mid-bright pixels with that in mid-dark pixels (ratio ~1 = Gaussian).
    M = [1 -2 1; -2 4 -2; 1 -2 1];
    r = abs(conv2(g, M, 'same'));                       % mostly noise
    m = imfilter(g, ones(7)/49, 'symmetric');           % local brightness
    darkPix   = m > 0.1 & m < 0.4;
    brightPix = m > 0.6 & m < 0.9;
    if mean(darkPix(:)) < 0.03 || mean(brightPix(:)) < 0.03
        q = 1;                                          % not enough pixels to tell
        return;
    end
    q = median(r(brightPix)) / median(r(darkPix));
end


function [centres, radii] = detectNoiseSpikes(spectrum, dcRadius, bgWindow, threshold, minR, maxR)
% ADAPTIVE notch detector: decides from THIS spectrum how many notches,
% where, and how big.
    background = medfilt2(spectrum, [bgWindow bgWindow], 'symmetric');   % normal level
    residual   = spectrum - background;                                   % what sticks out
    N = size(spectrum, 1);
    c = floor(N/2) + 1;
    [x, y] = meshgrid(1:N, 1:N);
    residual(hypot(x - c, y - c) <= dcRadius) = 0;                        % protect centre
    limit = mean(residual(:)) + threshold * std(residual(:));             % adaptive threshold
    spikeMask = residual > limit;
    labels = bwlabel(spikeMask, 8);                                       % connected components
    stats  = regionprops(labels, residual, 'WeightedCentroid', 'Area');
    centres = zeros(0, 2);
    radii   = zeros(0, 1);
    for i = 1:numel(stats)
        centre = stats(i).WeightedCentroid;
        if hypot(centre(1) - c, centre(2) - c) <= dcRadius
            continue;
        end
        r = 2 * sqrt(stats(i).Area / pi) + 1;
        centres(end+1, :) = centre;                                       %#ok<AGROW>
        radii(end+1, 1)   = min(max(r, minR), maxR);                      %#ok<AGROW>
    end
end


% ---------------- Filters ----------------

function H = buildNotchFilter(N, centres, radii)
% Gaussian notch-reject filter: 1 everywhere, 0 at each centre.
    [x, y] = meshgrid(1:N, 1:N);
    H = ones(N, N);
    for i = 1:size(centres, 1)
        D2 = (x - centres(i,1)).^2 + (y - centres(i,2)).^2;
        H  = H .* (1 - exp(-D2 / (2 * radii(i)^2)));
    end
end


function out = applyMask(g, H)
% Frequency-domain filtering of one channel: FFT -> multiply -> inverse FFT.
    out = real(ifft2(ifftshift(fftshift(fft2(g)) .* H)));
end


function [centres, radii] = fixedNotchPositions(N, noiseUV, radius)
% Fixed notch designed in advance for noise [u v]: a spot and its mirror.
    c = floor(N/2) + 1;
    centres = [c + noiseUV(1), c + noiseUV(2);
               c - noiseUV(1), c - noiseUV(2)];
    radii = [radius; radius];
end


function f = arithmeticMean3x3(g)
% Arithmetic mean filter written from the formula
%   f(x,y) = (1/mn) * sum of g over the 3x3 neighbourhood
    p = padarray(g, [1 1], 'replicate');
    f = zeros(size(g));
    for dx = -1:1
        for dy = -1:1
            f = f + p(2+dy:end-1+dy, 2+dx:end-1+dx);
        end
    end
    f = f / 9;
end


function f = alphaTrimmedMean(g, n, d)
% Alpha-trimmed mean: sort the n x n neighbourhood, drop d/2 lowest and
% d/2 highest values, average the rest.
    k = n * n;
    f = zeros(size(g));
    for r = (d/2 + 1):(k - d/2)
        f = f + ordfilt2(g, r, ones(n), 'symmetric');
    end
    f = f / (k - d);
end


function f = adaptiveMedian(g, Smax)
% Adaptive median filter (Gonzalez & Woods).
% Level A: is the median itself an impulse? If yes, grow the window.
% Level B: is the centre pixel an impulse? If yes, replace it by the median,
%          otherwise keep it (so detail is preserved).
    f    = g;
    done = false(size(g));
    for n = 3:2:Smax
        zmin = ordfilt2(g, 1,     ones(n), 'symmetric');
        zmax = ordfilt2(g, n*n,   ones(n), 'symmetric');
        zmed = medfilt2(g, [n n], 'symmetric');
        levelA  = (zmed > zmin) & (zmed < zmax) & ~done;   % median is not an impulse
        centreOK = (g > zmin) & (g < zmax);                % centre is not an impulse
        replace = levelA & ~centreOK;
        f(replace) = zmed(replace);                        % keep g where centreOK
        done = done | levelA;
    end
    f(~done) = zmed(~done);                                % window reached Smax
end


function f = adaptiveLocalFilter(g, noiseVar, n)
% Adaptive local noise reduction filter (Gonzalez & Woods):
%   f = g - (noiseVar / localVar) * (g - localMean)
% Flat areas (localVar ~ noiseVar) are smoothed strongly; edges
% (localVar >> noiseVar) are left almost untouched.
    k  = ones(n) / n^2;
    mL = imfilter(g, k, 'symmetric');
    vL = imfilter(g.^2, k, 'symmetric') - mL.^2;
    ratio = noiseVar ./ max(vL, noiseVar);                % never above 1
    f = g - ratio .* (g - mL);
end


function f = homomorphicFilter(g, factor, n)
% Speckle removal: the log transform (dynamic range compression) turns
% multiplicative noise into additive noise, the adaptive local filter
% removes it, and exp() undoes the log.
    e = 0.02;                                     % avoids log(0)
    L = log(g + e);
    s = estimateNoiseSigma(L);
    f = exp(adaptiveLocalFilter(L, factor * s^2, n)) - e;
end


% ---------------- Morphology ----------------

function n = countObjects(g)
% Morphological object counting:
% Otsu threshold -> opening (removes specks) -> hole filling ->
% remove tiny regions -> connected components.
    bw = g > graythresh(g);
    bw = imopen(bw, strel('disk', 2, 0));
    bw = imfill(bw, 'holes');
    bw = bwareaopen(bw, 30);
    [~, n] = bwlabel(bw, 8);
end


% ---------------- Figures ----------------

function fig = newFigure(pos)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', pos);
end


function saveFigure(fig, file, keepOpen)
    if nargin < 3, keepOpen = false; end
    saveas(fig, file);
    if keepOpen
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end
end
