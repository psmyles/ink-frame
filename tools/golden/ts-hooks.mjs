// Node module hooks so the unmodified opendithering TypeScript can run under Node:
// extensionless relative imports resolve to .ts, and the canvas-based resize is
// replaced by resize-stub.mjs (inputs are given already at the display size).
export async function resolve(specifier, context, next) {
  if (specifier.endsWith("/resize") && context.parentURL?.includes("/opendithering/")) {
    return next(new URL("./resize-stub.mjs", import.meta.url).href, context);
  }
  if (specifier.startsWith(".") && !/\.[cm]?[jt]s$/.test(specifier)) {
    return next(`${specifier}.ts`, context);
  }
  return next(specifier, context);
}
