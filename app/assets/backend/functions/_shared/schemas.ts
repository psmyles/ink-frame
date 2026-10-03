// Request schemas shared by both functions; they mirror components/schemas in
// shared/api/openapi.yaml.

import { z } from "npm:zod@4.6.5";

export const Uuid = z.uuid();
export const Sha256 = z.string().regex(/^[0-9a-f]{64}$/);
export const HwId = z.string().regex(/^[A-Za-z0-9:_-]{4,64}$/);
export const ModelId = z.string().regex(/^[a-z0-9][a-z0-9-]{1,63}$/);
export const FwVersion = z.string().max(32);
export const FrameName = z.string().trim().min(1).max(40);
export const DisplayName = z.string().trim().min(1).max(40);
export const LocalTime = z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/);
export const DisplayOrder = z.enum(["random", "sequential"]);
export const Timezone = z.string().max(64);

export const MAX_IMAGE_BYTES = 524288;
