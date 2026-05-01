// $lib/utils/imageResize.js
//
// Browser-Canvas-Helper: Resize Foto-Upload auf 512x512 WebP, strippt EXIF via Re-encode.
// Browser-only (createImageBitmap + canvas.toBlob — keine Server-Variante).
//
// - Center-Crop auf Quadrat (Avatar-Standard)
// - Output: image/webp bei quality 0.82 (~ <200KB fuer typische Fotos)
// - EXIF/GPS automatisch entfernt durch Canvas-Re-encode (Pixel-only Output)
//
// Pitfall-Source: .planning/research/PITFALLS.md C6 (EXIF-GPS-DSGVO).
// Spec: .planning/phases/00-cross-cutting-foundations/0-CONTEXT.md D-07/D-08.
// Konsumiert von: Phase 1 SELF-04 ProfilFotoSheet (zukuenftig).

const SIZE = 512;
const QUALITY = 0.82;

/**
 * Resize + Center-Crop ein File auf 512x512 WebP. EXIF wird durch Canvas-Re-encode entfernt.
 *
 * @param {File} file — Browser File-Object (image/* mime)
 * @returns {Promise<{ blob: Blob, mime: 'image/webp' }>}
 * @throws {Error} wenn canvas.toBlob null zurueckgibt (Browser ohne WebP-Support — sehr selten)
 */
export async function resizeImage(file) {
	const bitmap = await createImageBitmap(file);
	const canvas = document.createElement('canvas');
	canvas.width = SIZE;
	canvas.height = SIZE;
	const ctx = canvas.getContext('2d');

	// Center-Crop: nimm das kleinere Quadrat aus dem Original.
	const srcSize = Math.min(bitmap.width, bitmap.height);
	const sx = (bitmap.width - srcSize) / 2;
	const sy = (bitmap.height - srcSize) / 2;
	ctx.drawImage(bitmap, sx, sy, srcSize, srcSize, 0, 0, SIZE, SIZE);

	const blob = await new Promise((resolve, reject) => {
		canvas.toBlob(
			(b) => (b ? resolve(b) : reject(new Error('canvas.toBlob returned null (WebP nicht unterstuetzt?)'))),
			'image/webp',
			QUALITY
		);
	});

	// Memory: ImageBitmap kann gross sein; close() wenn verfuegbar (modern Browser).
	if (typeof bitmap.close === 'function') bitmap.close();

	return { blob, mime: 'image/webp' };
}
