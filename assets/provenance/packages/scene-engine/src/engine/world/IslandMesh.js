import * as THREE from 'three';
import { CONFIG, biomeLayers } from '../../config/constants.js';
import { simplex, texSimplex, smoothstep } from '../../utils/math.js';
import { IslandVegetationManager } from './IslandVegetationManager.js';
import { BeachDecorationManager } from './BeachDecorationManager.js';
import { sampleHeightData } from '../terrain/terrainHeight.js';

function getSortedBiomes() {
    return [...biomeLayers].sort((a, b) => a.h - b.h);
}

function getBiomeColor(height, targetColor) {
    const sorted = getSortedBiomes();
    if (height <= sorted[0].h) return targetColor.copy(sorted[0].threeColor);
    if (height >= sorted[sorted.length - 1].h) {
        return targetColor.copy(sorted[sorted.length - 1].threeColor);
    }

    for (let i = 0; i < sorted.length - 1; i++) {
        const curr = sorted[i];
        const next = sorted[i + 1];
        if (height >= curr.h && height <= next.h) {
            const t = smoothstep(curr.h, next.h, height);
            return targetColor.copy(curr.threeColor).lerp(next.threeColor, t);
        }
    }
    return targetColor;
}

function applyProceduralTexture(color, height, x, z) {
    const grain = texSimplex.noise(x * 0.35, z * 0.35);
    const patch = texSimplex.noise(x * 0.05, z * 0.05);

    if (height < 0) return;
    if (height < 15) {
        const lightnessVar = grain * 0.05;
        color.offsetHSL(0, 0, lightnessVar);
    } else if (height < 90) {
        if (patch > 0.2) {
            const dirtFactor = (patch - 0.2) * 0.15;
            const dirtColor = new THREE.Color(0x8b7d6b);
            color.lerp(dirtColor, dirtFactor);
        }
        color.offsetHSL(0, 0, grain * 0.04);
    } else {
        const rockNoise = Math.abs(grain);
        const darkness = rockNoise * 0.25;
        color.offsetHSL(0, -0.1, -darkness * 0.5);
        color.lerp(new THREE.Color(0x1a1a1a), darkness * 0.4);
    }
}

export class IslandMesh extends THREE.Group {
    constructor({ x, z, resolution = CONFIG.resolution, enableVegetation = true, enableDecorations, vegetationExclusions, worldOffset = 0 } = {}) {
        super();
        this.position.set(0, 0, 0);
        this.chunkX = x;
        this.chunkZ = z;
        this.size = CONFIG.chunkSize;
        this.resolution = resolution;
        this.enableVegetation = enableVegetation;
        this.enableDecorations = enableDecorations ?? enableVegetation;
        this.seaLevel = CONFIG.waterLevel;

        this.vegetationData = [];
        this.vegetationMeshes = [];
        this.vegetationManager = new IslandVegetationManager({
            seaLevel: this.seaLevel,
            enabled: this.enableVegetation,
            vegetationExclusions,
            worldOffset
        });
        this.decorationData = [];
        this.decorationMeshes = [];
        this.decorationManager = new BeachDecorationManager({
            seaLevel: this.seaLevel,
            enabled: this.enableDecorations
        });
        this.buildTerrain();
        if (this.enableVegetation) {
            this.createVegetation();
        }
        if (this.enableDecorations) {
            this.createDecorations();
        }
    }

    buildTerrain() {
        const geometry = new THREE.PlaneGeometry(
            this.size,
            this.size,
            this.resolution,
            this.resolution
        );
        geometry.rotateX(-Math.PI / 2);
        geometry.translate(this.chunkX * this.size, 0, this.chunkZ * this.size);

        const posAttr = geometry.attributes.position;
        const colors = [];
        const count = posAttr.count;
        const tempColor = new THREE.Color();
        this.vegetationManager.reset(this.enableVegetation);
        this.decorationManager.reset(this.enableDecorations);

        for (let i = 0; i < count; i++) {
            const wx = posAttr.getX(i);
            const wz = posAttr.getZ(i);

            const { height, normalized, isUnderwater } = sampleHeightData(wx, wz);

            posAttr.setY(i, height);

            getBiomeColor(height, tempColor);
            applyProceduralTexture(tempColor, height, wx, wz);

            if (isUnderwater) {
                const depth = -height / 50;
                if (depth < 0.15) {
                    let caustic = simplex.noise(wx * 0.2, wz * 0.2);
                    caustic += simplex.noise(wx * 0.2 + 100, wz * 0.2 + 100) * 0.5;
                    caustic = Math.pow(Math.abs(caustic), 3.0);
                    tempColor.lerp(new THREE.Color(0xffffff), caustic * 0.25 * (1.0 - depth / 0.15));
                }
            }
            colors.push(tempColor.r, tempColor.g, tempColor.b);

            const sample = { height, normalized, isUnderwater };
            if (this.enableVegetation) {
                this.vegetationManager.tryAddInstance(wx, wz, sample);
            }
            if (this.enableDecorations) {
                this.decorationManager.tryAddInstance(wx, wz, sample);
            }
        }

        geometry.setAttribute(
            'color',
            new THREE.Float32BufferAttribute(colors, 3)
        );
        geometry.computeVertexNormals();

        const material = new THREE.MeshStandardMaterial({
            vertexColors: true,
            roughness: 0.9,
            metalness: 0.1,
            flatShading: false
        });

        this.terrainMesh = new THREE.Mesh(geometry, material);
        this.terrainMesh.castShadow = true;
        this.terrainMesh.receiveShadow = true;
        this.add(this.terrainMesh);

        this.vegetationData = this.enableVegetation ? this.vegetationManager.getInstances() : [];
        this.decorationData = this.enableDecorations ? this.decorationManager.getInstances() : [];
    }

    createVegetation() {
        // Ghost-only candidates still consume legacy build-time tilt RNG.
        const meshes = this.vegetationManager.attach(this);
        this.vegetationMeshes = meshes || [];
    }

    createDecorations() {
        if (!this.decorationData.length) return;
        const meshes = this.decorationManager.attach(this);
        this.decorationMeshes = meshes || [];
    }

    updateColors() {
        if (!this.terrainMesh) return;
        const geometry = this.terrainMesh.geometry;
        const pos = geometry.attributes.position;
        const colors = geometry.attributes.color;
        const tempColor = new THREE.Color();

        for (let i = 0; i < pos.count; i++) {
            const height = pos.getY(i);
            const wx = pos.getX(i);
            const wz = pos.getZ(i);
            getBiomeColor(height, tempColor);
            applyProceduralTexture(tempColor, height, wx, wz);
            if (height < 0) {
                const depth = -height / 50;
                if (depth < 0.15) {
                    tempColor.lerp(new THREE.Color(0xffffff), 0.1 * (1.0 - depth / 0.15));
                }
            }
            colors.setXYZ(i, tempColor.r, tempColor.g, tempColor.b);
        }
        colors.needsUpdate = true;
    }

    dispose() {
        if (this.terrainMesh) {
            this.remove(this.terrainMesh);
            this.terrainMesh.geometry.dispose();
            this.terrainMesh.material.dispose();
            this.terrainMesh = null;
        }
        if (this.vegetationManager) {
            this.vegetationManager.dispose(this);
            this.vegetationMeshes = [];
            this.vegetationData = [];
        }
        if (this.decorationManager) {
            this.decorationManager.dispose(this);
            this.decorationMeshes = [];
            this.decorationData = [];
        }
    }
}
