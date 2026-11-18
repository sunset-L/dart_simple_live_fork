import { safeImage } from "../services/media";

export function Picture({
  src,
  className,
  alt = "",
  onError,
}: {
  src?: string | null;
  className?: string;
  alt?: string;
  onError?: () => void;
}) {
  return (
    <img
      src={safeImage(src)}
      className={className}
      alt={alt}
      loading="lazy"
      referrerPolicy="no-referrer"
      onError={(event) => {
        if (onError) onError();
        else if (!event.currentTarget.src.endsWith("/assets/logo.png"))
          event.currentTarget.src = "/assets/logo.png";
      }}
    />
  );
}
