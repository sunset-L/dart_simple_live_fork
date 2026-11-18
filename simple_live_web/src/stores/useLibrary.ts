import { useCallback, useEffect, useState } from "react";
import {
  loadLibrary,
  refreshLibrary,
  saveLibrary,
  watchLibrary,
} from "./libraryStorage";
import type { Library } from "../types/library";
export function useLibrary() {
  const [data, setData] = useState(() => loadLibrary().data);
  useEffect(() => {
    const reload = () => setData(loadLibrary().data);
    const stop = watchLibrary(reload);
    reload();
    void refreshLibrary();
    return stop;
  }, []);
  const update = useCallback(async (transform: (data: Library) => Library) => {
    const current = loadLibrary();
    if (current.error) throw new Error(current.error);
    const next = transform(current.data);
    await saveLibrary(next);
  }, []);
  return { data, update };
}
