// shared/presets.json with valid model ids: used by gen-seed.ts (seed.sql) and
// bundle-backend.ts (the setup wizard's model list).

// Preset ids come from ink-frame-lab and aren't valid model ids (spaces, dots,
// capitals). Ids that firmware builds depend on are pinned here; the rest are slugged.
const MODEL_ID_OVERRIDES: Record<string, string> = {
  "reTerminal E1002 7.3": "reterminal-e1002",
};

type Presets = {
  devices: { id: string; name: string; resolution: { w: number; h: number }; palette: string }[];
  palettes: { id: string; name: string; colors: { name: string; color: string; deviceColor: string }[] }[];
};

export type Model = { id: string; name: string; width: number; height: number; palette: string };

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

export async function loadPresets(): Promise<{ palettes: Presets["palettes"]; models: Model[] }> {
  const presets: Presets = JSON.parse(await Deno.readTextFile(new URL("../../shared/presets.json", import.meta.url)));
  const seen = new Set<string>();
  const models = presets.devices.map((d) => {
    const id = MODEL_ID_OVERRIDES[d.id] ?? slug(d.id);
    if (!/^[a-z0-9][a-z0-9-]{1,63}$/.test(id)) throw new Error(`bad model id ${id} (from ${d.id})`);
    if (seen.has(id)) throw new Error(`duplicate model id ${id}`);
    seen.add(id);
    return { id, name: d.name, width: d.resolution.w, height: d.resolution.h, palette: d.palette };
  });
  return { palettes: presets.palettes, models };
}
