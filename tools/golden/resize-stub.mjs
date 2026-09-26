// Stands in for opendithering's canvas resize: the "source" is already an ImageData
// of the display size, so it is only copied (the pipeline mutates its input).
export function resizeImage(source, srcW, srcH, dstW, dstH) {
  if (source.width !== dstW || source.height !== dstH) throw new Error("vector inputs must be pre-sized");
  return new ImageData(new Uint8ClampedArray(source.data), dstW, dstH);
}
