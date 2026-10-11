import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

export const Assets = {
    palmGeo: null,
    palmMat: new THREE.MeshStandardMaterial({
        color: 0x557a40, roughness: 0.8, side: THREE.DoubleSide, flatShading: false
    }),
    broadleafGeo: null,
    broadleafMat: new THREE.MeshStandardMaterial({
        vertexColors: true, roughness: 0.9, metalness: 0.05, flatShading: true
    }),
    grassGeo: null,
    grassMat: new THREE.MeshStandardMaterial({
        vertexColors: true, roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide, flatShading: true
    }),
    shellGeo: null,
    shellMat: new THREE.MeshStandardMaterial({
        vertexColors: true, roughness: 0.85, metalness: 0.05, flatShading: true
    }),
    starfishGeo: null,
    starfishMat: new THREE.MeshStandardMaterial({
        vertexColors: true, roughness: 0.9, metalness: 0.02, flatShading: true
    }),
    pebbleGeo: null,
    pebbleMat: new THREE.MeshStandardMaterial({
        vertexColors: true, roughness: 0.95, metalness: 0.02, flatShading: true
    }),
    waterTexture: null,
    foamTexture: null
};

let cachedAnisotropy = null;

function getMaxAnisotropy() {
    if (cachedAnisotropy !== null) return cachedAnisotropy;
    try {
        const renderer = new THREE.WebGLRenderer();
        cachedAnisotropy = renderer.capabilities.getMaxAnisotropy() || 1;
        renderer.dispose();
    } catch (err) {
        cachedAnisotropy = 1;
    }
    return cachedAnisotropy;
}

function configureTexture(texture) {
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.anisotropy = getMaxAnisotropy();
    return texture;
}

function createFallbackTexture(color) {
    const [r, g, b] = color;
    const data = new Uint8Array([r, g, b, 255]);
    const texture = new THREE.DataTexture(data, 1, 1);
    texture.needsUpdate = true;
    return texture;
}

export async function loadResources() {
    const loader = new THREE.TextureLoader();
    const loadTex = (url, fallbackColor) => new Promise((resolve) => {
        loader.load(
            url,
            (texture) => resolve(configureTexture(texture)),
            undefined,
            () => {
                const fallback = configureTexture(createFallbackTexture(fallbackColor));
                console.warn(`[Assets] Failed to load ${url}. Using fallback texture.`);
                resolve(fallback);
            }
        );
    });

    const [water, foam] = await Promise.all([
        loadTex('textures/waternormals.jpg', [128, 128, 255]),
        loadTex('textures/foam.png', [255, 255, 255])
    ]);

    Assets.waterTexture = water;
    Assets.foamTexture = foam;
}

export function createPalmTreeGeometry() {
    const geometries = [];

    // Trunk: chained cylinders following a gentle curve so segments connect without gaps
    const trunkSegments = 7;
    const segmentHeight = 2.4;
    let pos = new THREE.Vector3(0, 0, 0);
    let orientation = new THREE.Quaternion();
    let topPos = pos.clone();
    let topOrientation = orientation.clone();

    for (let i = 0; i < trunkSegments; i++) {
        const radiusBottom = Math.max(0.18, 0.6 - i * 0.07);
        const radiusTop = Math.max(0.14, radiusBottom - 0.05);
        const trunkGeo = new THREE.CylinderGeometry(
            radiusTop,
            radiusBottom,
            segmentHeight,
            8,
            1,
            false
        );
        trunkGeo.translate(0, segmentHeight / 2, 0);
        trunkGeo.applyQuaternion(orientation);
        trunkGeo.translate(pos.x, pos.y, pos.z);
        geometries.push(trunkGeo);

        const topOffset = new THREE.Vector3(0, segmentHeight, 0).applyQuaternion(orientation);
        pos = pos.clone().add(topOffset);
        topPos = pos.clone();
        topOrientation = orientation.clone();

        if (i < trunkSegments - 1) {
            const tiltQuat = new THREE.Quaternion().setFromEuler(
                new THREE.Euler(0.08, 0.05, 0.04)
            );
            orientation = orientation.clone().multiply(tiltQuat);
        }
    }

    // Leaves: bend planes, pivot at base, align to trunk tip
    const leafCount = 8;
    const leafWidth = 3.2;
    const leafLength = 9.5;

    for (let i = 0; i < leafCount; i++) {
        const leafGeo = new THREE.PlaneGeometry(leafWidth, leafLength, 2, 5);
        const posAttr = leafGeo.attributes.position;

        for (let j = 0; j < posAttr.count; j++) {
            const y = posAttr.getY(j);
            const t = (y + leafLength / 2) / leafLength; // 0..1 along length
            const bend = -Math.pow(t, 1.2) * 3.0;
            posAttr.setZ(j, posAttr.getZ(j) + bend);
        }
        leafGeo.computeVertexNormals();

        // Place root at local origin so it seats on trunk top
        leafGeo.translate(0, leafLength / 2, 0);

        const yaw = (i / leafCount) * Math.PI * 2;
        const droop = -Math.PI / 3;
        const leafOrientation = topOrientation
            .clone()
            .multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0)))
            .multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(droop, 0, 0)));

        leafGeo.applyQuaternion(leafOrientation);

        const crownOffset = new THREE.Vector3(0, 0.25, 0).applyQuaternion(topOrientation);
        const leafBase = topPos.clone().add(crownOffset);
        leafGeo.translate(leafBase.x, leafBase.y, leafBase.z);

        geometries.push(leafGeo);
    }

    return mergeGeometries(geometries);
}

function addVertexColor(geometry, color) {
    const c = new THREE.Color(color);
    const count = geometry.attributes.position.count;
    const colors = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
        colors[i * 3] = c.r;
        colors[i * 3 + 1] = c.g;
        colors[i * 3 + 2] = c.b;
    }
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
}

export function createBroadleafTreeGeometry() {
    const parts = [];

    // Trunk
    const trunk = new THREE.CylinderGeometry(0.28, 0.38, 3.6, 8, 1, false);
    trunk.translate(0, 1.8, 0);
    addVertexColor(trunk, 0x6b4b2b);
    parts.push(trunk);

    // Foliage layers
    const foliageColors = [0x4f7d30, 0x5c8c35, 0x3f6528];
    const foliageHeights = [3.2, 4.2, 5.0];
    const foliageScales = [1.6, 1.2, 0.8];

    foliageHeights.forEach((h, idx) => {
        const cone = new THREE.ConeGeometry(1.4 * foliageScales[idx], 1.8 * foliageScales[idx], 7, 1, true);
        cone.translate(0, h, 0);
        const tilt = new THREE.Quaternion().setFromEuler(new THREE.Euler(
            (Math.random() - 0.5) * 0.1,
            (Math.random() - 0.5) * 0.4,
            (Math.random() - 0.5) * 0.1
        ));
        cone.applyQuaternion(tilt);
        addVertexColor(cone, foliageColors[idx % foliageColors.length]);
        parts.push(cone);
    });

    const crown = new THREE.SphereGeometry(0.6, 8, 6);
    crown.translate(0, 5.4, 0);
    addVertexColor(crown, 0x396c24);
    parts.push(crown);

    return mergeGeometries(parts);
}

export function createGrassPatchGeometry() {
    const blades = [];
    const bladeCount = 8;
    const width = 0.22;
    const height = 1.6;

    for (let i = 0; i < bladeCount; i++) {
        const plane = new THREE.PlaneGeometry(width, height, 1, 3);
        plane.translate(0, height * 0.5, 0);

        const colorBottom = new THREE.Color(0x2f5a1e);
        const colorTop = new THREE.Color(0x7fce53);
        const count = plane.attributes.position.count;
        const colors = new Float32Array(count * 3);

        for (let j = 0; j < count; j++) {
            const yRaw = plane.attributes.position.getY(j) / height;
            const y = Math.min(1, Math.max(0, yRaw)); // clamp to avoid NaN from negative roots
            const c = colorBottom.clone().lerp(colorTop, y);
            colors[j * 3] = c.r;
            colors[j * 3 + 1] = c.g;
            colors[j * 3 + 2] = c.b;

            const bendBack = Math.pow(y, 1.5) * 0.16;
            const lateral = (Math.random() - 0.5) * 0.04 * y;
            plane.attributes.position.setZ(j, plane.attributes.position.getZ(j) - bendBack);
            plane.attributes.position.setX(j, plane.attributes.position.getX(j) + lateral);
        }
        plane.setAttribute('color', new THREE.BufferAttribute(colors, 3));
        plane.computeVertexNormals();

        // Spread blades around center with slight outward tilt and radial offset
        const yaw = (Math.PI * 2 * i) / bladeCount;
        const radius = 0.08 + Math.random() * 0.08;
        plane.translate(Math.cos(yaw) * radius, 0, Math.sin(yaw) * radius);
        const outwardTilt = -0.25 - Math.random() * 0.15;
        plane.rotateZ(outwardTilt);
        plane.rotateY(yaw);
        blades.push(plane);
    }

    return mergeGeometries(blades);
}

export function createShellGeometry() {
    const shell = new THREE.SphereGeometry(0.35, 16, 12, 0, Math.PI);
    shell.scale(1.2, 0.6, 1);
    shell.rotateZ(Math.PI); // open side down

    const colorBase = new THREE.Color(0xf2e5c8);
    const colorRim = new THREE.Color(0xe4d3ad);
    const count = shell.attributes.position.count;
    const colors = new Float32Array(count * 3);

    for (let i = 0; i < count; i++) {
        const v = shell.attributes.position.getY(i) * 1.5 + 0.5; // favor rim on outer edge
        const c = colorBase.clone().lerp(colorRim, Math.min(1, Math.max(0, v)));
        colors[i * 3] = c.r;
        colors[i * 3 + 1] = c.g;
        colors[i * 3 + 2] = c.b;
    }
    shell.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    return shell;
}

export function createStarfishGeometry() {
    const shape = new THREE.Shape();
    const points = [];
    const arms = 5;
    const inner = 0.18;
    const outer = 0.45;
    for (let i = 0; i < arms * 2; i++) {
        const r = i % 2 === 0 ? outer : inner;
        const a = (i / (arms * 2)) * Math.PI * 2;
        points.push(new THREE.Vector2(Math.cos(a) * r, Math.sin(a) * r));
    }
    shape.moveTo(points[0].x, points[0].y);
    points.slice(1).forEach(p => shape.lineTo(p.x, p.y));
    shape.closePath();

    const extrude = new THREE.ExtrudeGeometry(shape, { depth: 0.1, bevelEnabled: true, bevelSize: 0.04, bevelThickness: 0.05, bevelSegments: 2 });
    extrude.translate(0, 0.05, 0);
    extrude.rotateX(-Math.PI / 2);

    const colorA = new THREE.Color(0xf08f55);
    const colorB = new THREE.Color(0xe36a3c);
    const pos = extrude.attributes.position;
    const count = pos.count;
    const colors = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
        const y = pos.getY(i);
        const t = Math.min(1, Math.max(0, (y + 0.1) * 3));
        const c = colorA.clone().lerp(colorB, t);
        colors[i * 3] = c.r;
        colors[i * 3 + 1] = c.g;
        colors[i * 3 + 2] = c.b;
    }
    extrude.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    return extrude;
}

export function createPebbleGeometry() {
    const pebble = new THREE.IcosahedronGeometry(0.28, 1);
    pebble.scale(1.2, 0.5, 1);
    const color = new THREE.Color(0x7a7068);
    addVertexColor(pebble, color);
    return pebble;
}
