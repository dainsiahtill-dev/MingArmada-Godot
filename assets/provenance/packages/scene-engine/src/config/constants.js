import * as THREE from 'three';

export const CONFIG = {
    chunkSize: 250,
    resolution: 128,
    waterLevel: 0.60,
    defaultWaterMode: 'projected',
    colors: {
        deep: new THREE.Color('#008991'),    // 深色的墨蓝
        shallow: new THREE.Color('#00b6ad'), // 透亮的青蓝
        foam: new THREE.Color(0xffffff)
    },
    minWorldH: -50,
    maxWorldH: 150,
    enableUI: true, // 设为 false 可完全禁用 UI (例如发布纯游戏版本时)
    heightmap: {
        mode: 'procedural',
        worldSize: 4000,
        origin: { x: -2000, z: -2000 },
        wrap: false,
        remoteURL: '',
        autoLoadRemote: false
    }
};

export const DEFAULT_LAYERS = [
    { id: 'deep',    h: -50,  color: '#002b4d', label: 'Deep Sea' },
    { id: 'shallow', h: -35,  color: '#002b4d', label: 'Shallows' },
    { id: 'beach',   h: -5,   color: '#8B7D6B', label: 'Wet Sand' },
    { id: 'sand',    h: 2,    color: '#E6DABF', label: 'Dry Sand' },
    { id: 'grass',   h: 10,   color: '#597d3e', label: 'Grass' },
    { id: 'forest',  h: 60,   color: '#284024', label: 'Jungle' },
    { id: 'rock',    h: 100,  color: '#5a5552', label: 'Rock' },
    { id: 'peak',    h: 140,  color: '#888888', label: 'Peak' }
];

// 深拷贝并初始化 THREE.Color 对象
export let biomeLayers = JSON.parse(JSON.stringify(DEFAULT_LAYERS));
biomeLayers.forEach(l => l.threeColor = new THREE.Color(l.color));

export const globalUniforms = {
    uTime: { value: 0 },
    uSunPosition: { value: new THREE.Vector3() },
    uColorDeep: { value: CONFIG.colors.deep },
    uColorShallow: { value: CONFIG.colors.shallow },
    uColorFoam: { value: CONFIG.colors.foam }
};

export const WATER_CONTROL_GROUPS = [
    {
        id: 'shoreline',
        title: '岸线海浪',
        controls: [
            {
                id: 'shoreFoamStrength',
                label: '岸线泡沫强度',
                min: 0,
                max: 2,
                step: 0.05,
                default: 0.9,
                precision: 2,
                uniform: 'uShoreFoamStrength'
            },
            {
                id: 'shoreFoamSpeed',
                label: '岸线泡沫速度',
                min: 0,
                max: 2,
                step: 0.01,
                default: 0.4,
                precision: 2,
                uniform: 'uShoreFoamSpeed'
            },
            {
                id: 'shoreFoamScale',
                label: '岸线泡沫尺度',
                min: 0.01,
                max: 0.3,
                step: 0.005,
                default: 0.06,
                precision: 3,
                uniform: 'uShoreFoamScale'
            },
            {
                id: 'shoreFoamWidth',
                label: '岸线泡沫宽度',
                min: 0.05,
                max: 0.6,
                step: 0.01,
                default: 0.2,
                precision: 2,
                uniform: 'uShoreFoamWidth'
            },
            {
                id: 'shoreStrength',
                label: '岸线整体强度',
                min: 0,
                max: 2,
                step: 0.05,
                default: 0.6,
                precision: 2,
                uniform: 'uShoreStrength'
            },
            {
                id: 'shoreFadeStart',
                label: '岸线淡入起点',
                min: -5,
                max: 10,
                step: 0.1,
                default: 2.0,
                precision: 1,
                uniform: 'uShoreFadeStart'
            },
            {
                id: 'shoreFadeEnd',
                label: '岸线淡出终点',
                min: 0.1,
                max: 20,
                step: 0.1,
                default: 8.0,
                precision: 1,
                uniform: 'uShoreFadeEnd'
            },
            {
                id: 'shoreNoiseScale',
                label: '岸线噪声尺度',
                min: 0.5,
                max: 6,
                step: 0.1,
                default: 2.4,
                precision: 2,
                uniform: 'uShoreNoiseScale'
            },
            {
                id: 'shoreNoiseSpeed',
                label: '岸线噪声速度',
                min: 0,
                max: 1,
                step: 0.01,
                default: 0.25,
                precision: 2,
                uniform: 'uShoreNoiseSpeed'
            },
            {
                id: 'shoreFeather',
                label: '岸线羽化',
                min: 0.2,
                max: 3,
                step: 0.05,
                default: 1.1,
                precision: 2,
                uniform: 'uShoreFeather'
            },
            {
                id: 'shoreDepthRange',
                label: '岸线深度范围 (m)',
                min: 2,
                max: 20,
                step: 0.5,
                default: 8,
                precision: 1,
                uniform: 'uShoreDepthRange'
            },
            {
                id: 'shoreBandSpeed',
                label: '岸线波速',
                min: 0,
                max: 3,
                step: 0.05,
                default: 0.6,
                precision: 2,
                uniform: 'uShoreBandSpeed'
            },
            {
                id: 'shoreBandScale',
                label: '岸线波纹密度',
                min: 1,
                max: 8,
                step: 0.1,
                default: 4,
                precision: 2,
                uniform: 'uShoreBandScale'
            },
            {
                id: 'shoreBandTimeJitter',
                label: '波纹时间扰动',
                min: 0,
                max: 1,
                step: 0.05,
                default: 0.5,
                precision: 2,
                uniform: 'uShoreBandTimeJitter'
            },
            {
                id: 'shoreBandSpeedJitter',
                label: '波纹速度扰动',
                min: 0,
                max: 1,
                step: 0.05,
                default: 0.6,
                precision: 2,
                uniform: 'uShoreBandSpeedJitter'
            },
            {
                id: 'shoreBandShapeJitter',
                label: '波纹形状扰动',
                min: 0,
                max: 1,
                step: 0.05,
                default: 0.45,
                precision: 2,
                uniform: 'uShoreBandShapeJitter'
            },
            {
                id: 'shoreFoamDetail',
                label: '泡沫细节',
                min: 0,
                max: 1,
                step: 0.05,
                default: 0.3,
                precision: 2,
                uniform: 'uShoreFoamDetail'
            },
            {
                id: 'shoreClusterScale',
                label: '泡沫簇尺度',
                min: 0.5,
                max: 5,
                step: 0.05,
                default: 1.6,
                precision: 2,
                uniform: 'uShoreClusterScale'
            },
            {
                id: 'shoreClusterJitter',
                label: '泡沫簇扰动',
                min: 0,
                max: 1,
                step: 0.05,
                default: 0.55,
                precision: 2,
                uniform: 'uShoreClusterJitter'
            },
            {
                id: 'shoreCascadeCount',
                label: '浪带数量',
                min: 0,
                max: 4,
                step: 1,
                default: 2,
                precision: 0,
                uniform: 'uShoreCascadeCount'
            },
            {
                id: 'shoreCascadeIntensity',
                label: '浪带强度',
                min: 0,
                max: 1.5,
                step: 0.05,
                default: 0.6,
                precision: 2,
                uniform: 'uShoreCascadeIntensity'
            },
            {
                id: 'shoreCascadeSpacing',
                label: '浪带间距',
                min: 0.05,
                max: 0.5,
                step: 0.01,
                default: 0.18,
                precision: 2,
                uniform: 'uShoreCascadeSpacing'
            },
            {
                id: 'shoreCascadeSpeed',
                label: '浪带速度',
                min: 0,
                max: 2,
                step: 0.05,
                default: 0.8,
                precision: 2,
                uniform: 'uShoreCascadeSpeed'
            }
        ]
    }
];

export const waterParams = {};
export const waterUniforms = {};

WATER_CONTROL_GROUPS.forEach(group => {
    group.controls.forEach(control => {
        waterParams[control.id] = control.default;
        waterUniforms[control.uniform] = { value: control.default };
    });
});

export const FFT_WATER_CONTROLS = [
    {
        id: 'fftWaterHeight',
        param: 'waterHeight',
        label: '水面高度 (m)',
        min: -20,
        max: 30,
        step: 0.5,
        default: 0,
        precision: 1,
        unit: ' m'
    },
    {
        id: 'fftTileSize',
        param: 'size',
        label: '频谱平铺尺寸 (m)',
        min: 100,
        max: 1500,
        step: 10,
        default: 350,
        precision: 0,
        unit: ' m'
    },
    {
        id: 'fftGeometrySize',
        param: 'geometrySize',
        label: '渲染几何范围 (m)',
        min: 800,
        max: 6000,
        step: 50,
        default: 2000,
        precision: 0,
        unit: ' m'
    },
    {
        id: 'fftShoreBlendRange',
        param: 'shoreBlendRange',
        label: '岸线过渡范围 (m)',
        min: 2,
        max: 60,
        step: 0.5,
        default: 14,
        precision: 1,
        unit: ' m'
    },
    {
        id: 'fftShoreFoamStrength',
        param: 'shoreFoamStrength',
        label: '岸线泡沫强度',
        min: 0,
        max: 2,
        step: 0.05,
        default: 0.7,
        precision: 2
    },
    {
        id: 'fftMinOpacity',
        param: 'minOpacity',
        label: '最小透明度',
        min: 0.05,
        max: 1.0,
        step: 0.05,
        default: 0.45,
        precision: 2
    },
    {
        id: 'fftDepthFogStrength',
        param: 'depthFogStrength',
        label: '深度雾强度',
        min: 0,
        max: 1,
        step: 0.05,
        default: 0.45,
        precision: 2
    },
    {
        id: 'fftDepthFogFalloff',
        param: 'depthFogFalloff',
        label: '深度雾衰减',
        min: 0.2,
        max: 4,
        step: 0.05,
        default: 1.2,
        precision: 2
    },
    {
        id: 'fftWindSpeed',
        param: 'windSpeed',
        label: '风速 (m/s)',
        min: 2,
        max: 40,
        step: 0.5,
        default: 16,
        precision: 1,
        unit: ' m/s'
    },
    {
        id: 'fftWindDirection',
        param: 'windDirection',
        label: '风向 (度)',
        min: 0,
        max: 360,
        step: 1,
        default: 45,
        precision: 0,
        unit: '度'
    },
    {
        id: 'fftChoppiness',
        param: 'choppiness',
        label: '浪峰锐度',
        min: 0.6,
        max: 3.0,
        step: 0.05,
        default: 1.5,
        precision: 2
    },
    {
        id: 'fftExposure',
        param: 'exposure',
        label: '曝光强度',
        min: 0.2,
        max: 1.2,
        step: 0.05,
        default: 0.4,
        precision: 2
    }
];

export const FFT_PARAM_DEFAULTS = Object.freeze(FFT_WATER_CONTROLS.reduce((acc, control) => {
    acc[control.param] = control.default;
    return acc;
}, {}));

export const ORIGINAL_WATER_CONTROLS = [
    {
        id: 'originalWaterHeight',
        param: 'height',
        label: '水面高度 (m)',
        min: -30,
        max: 30,
        step: 0.5,
        default: 0,
        precision: 1,
        unit: ' m'
    },
    {
        id: 'originalWaterAlpha',
        param: 'alpha',
        label: '透明度',
        min: 0.1,
        max: 1.0,
        step: 0.01,
        default: 0.85,
        precision: 2
    },
    {
        id: 'originalWaterDistortion',
        param: 'distortionScale',
        label: '畸变强度',
        min: 0.2,
        max: 8,
        step: 0.1,
        default: 4.0,
        precision: 2
    },
    {
        id: 'originalWaterWaveSize',
        param: 'size',
        label: '波纹尺寸倍数',
        min: 0.5,
        max: 4,
        step: 0.1,
        default: 1.4,
        precision: 1
    },
    {
        id: 'originalWaterFlowSpeed',
        param: 'flowSpeed',
        label: '水流速度倍数',
        min: 0.25,
        max: 2.5,
        step: 0.05,
        default: 1.0,
        precision: 2
    },
    {
        id: 'originalWaterColor',
        param: 'waterColor',
        label: '水面颜色',
        type: 'color',
        default: '#0f7d99'
    },
    {
        id: 'originalSunColor',
        param: 'sunColor',
        label: '高光颜色',
        type: 'color',
        default: '#ffffff'
    }
];

export const ORIGINAL_WATER_PARAM_DEFAULTS = Object.freeze(ORIGINAL_WATER_CONTROLS.reduce((acc, control) => {
    acc[control.param] = control.default;
    return acc;
}, {}));

export const originalWaterParams = { ...ORIGINAL_WATER_PARAM_DEFAULTS };
