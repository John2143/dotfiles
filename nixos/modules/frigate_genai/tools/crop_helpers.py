"""Crop coordinate validation helpers."""

def validate_crop_coords(x1: float, y1: float, x2: float, y2: float) -> tuple[float, float, float, float, list[str]]:
    """Validate and clamp crop coordinates to 0-1 range.
    
    Returns: (clamped_x1, clamped_y1, clamped_x2, clamped_y2, warnings)
    """
    warnings = []
    
    # Clamp to 0-1 range
    x1_clamped = max(0.0, min(1.0, x1))
    y1_clamped = max(0.0, min(1.0, y1))
    x2_clamped = max(0.0, min(1.0, x2))
    y2_clamped = max(0.0, min(1.0, y2))
    
    # Warn if coordinates were out of bounds
    if x1 != x1_clamped or y1 != y1_clamped or x2 != x2_clamped or y2 != y2_clamped:
        warnings.append(
            f"Coordinates clamped to valid range 0.0-1.0 "
            f"(original: x1={x1:.2f} y1={y1:.2f} x2={x2:.2f} y2={y2:.2f})"
        )
    
    # Check if crop region is too narrow
    width = x2_clamped - x1_clamped
    height = y2_clamped - y1_clamped
    
    if width < 0.05:
        warnings.append(
            f"Crop width is very narrow ({width:.3f} = ~{int(width * 4512)}px on 4K). "
            f"Consider wider bounds if subject is cut off."
        )
    if height < 0.05:
        warnings.append(
            f"Crop height is very narrow ({height:.3f} = ~{int(height * 2512)}px on 4K). "
            f"Consider wider bounds if subject is cut off."
        )
    
    return x1_clamped, y1_clamped, x2_clamped, y2_clamped, warnings
