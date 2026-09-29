export const initialize: (model: Uint8Array) => void;
export const run: (
  input: Float32Array,
  height: number,
  width: number,
) => { data: Float32Array; shape: number[] };
export const close: () => void;
