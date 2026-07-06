// Dell PowerEdge R740 Floor Standoffs
//
// Print 4 in PETG or ABS.  Keeps a 2U server off the floor
// for dust clearance and bottom intake airflow.
//
// Adjust dimensions at the top, then render (F6) and export STL.
// The `layout()` module arranges all 4 pieces for a single print.

// ── User parameters ───────────────────────────────────────
STANDOFF_H  = 50;   // total height (mm) — clearance off floor
WALL        = 3;    // shell thickness (mm)
FILLET      = 5;    // corner fillet radius (mm)

// ── Chassis measurements (Dell R740 bottom panel) ─────────
// The R740's rubber feet are ~15x15mm squares positioned at
// the four corners of the flat bottom plate, inset slightly
// from the outer edge.
FOOT_W      = 15;   // rubber foot width (mm)
FOOT_D      = 15;   // rubber foot depth (mm)
FOOT_POCKET = 2;    // recess depth for the foot to sit in (mm)

// Overall block size — wide enough for stability
BLOCK_W     = 80;   // width (mm, left-right)
BLOCK_D     = 65;   // depth (mm, front-back)

// ── Calculated internals ──────────────────────────────────
POCKET_W = BLOCK_W - WALL * 2 - 4;  // pocket width (unused)
POCKET_D = BLOCK_D - WALL * 2 - 4;  // pocket depth (unused)

// ── Modules ───────────────────────────────────────────────
module standoff() {
  difference() {
    // Outer shell — rounded block
    linear_extrude(height = STANDOFF_H)
      offset(r = FILLET)
        square([BLOCK_W, BLOCK_D], center = true);

    // Hollow cavity — saves filament, still strong enough
    // with 3mm walls + 50mm of PETG above the foot pocket.
    translate([0, 0, WALL])
      linear_extrude(height = STANDOFF_H - WALL + 0.1)
        offset(r = FILLET - 1)
          square([BLOCK_W - WALL * 2, BLOCK_D - WALL * 2],
                 center = true);

    // Foot pocket — recess on top surface for rubber foot
    translate([0, 0, STANDOFF_H - FOOT_POCKET])
      linear_extrude(height = FOOT_POCKET + 0.1)
        square([FOOT_W + 2, FOOT_D + 2], center = true);
  }
}

// ── Layout helper ─────────────────────────────────────────
// Places 4 standoffs on a single print bed.
module layout(gap = 10) {
  x = BLOCK_W + gap;
  y = BLOCK_D + gap;

  translate([-x / 2,  y / 2, 0]) standoff();    // front-left
  translate([ x / 2,  y / 2, 0]) standoff();    // front-right
  translate([-x / 2, -y / 2, 0]) standoff();    // rear-left
  translate([ x / 2, -y / 2, 0]) standoff();    // rear-right
}

// ── Render ────────────────────────────────────────────────
// Comment/uncomment to switch between print layout and single preview.
layout(gap = 10);
// standoff();
