"""OS-level input simulation."""

from .planner import KeyPlan, plan, plan_click, plan_combo, plan_key, plan_slide, plan_text
from .simulator import DEAD_ZONE, MAX_SPEED, InputSimulator

__all__ = [
    "KeyPlan",
    "plan",
    "plan_click",
    "plan_combo",
    "plan_key",
    "plan_slide",
    "plan_text",
    "InputSimulator",
    "MAX_SPEED",
    "DEAD_ZONE",
]
