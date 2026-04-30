import curses
import random
import time
import math
from typing import List, Optional, Tuple, Any


# --- Configuration ---
class Config:
    """Centralized configuration for the simulation."""

    # Screen & FPS
    TARGET_FPS = 30
    FRAME_TIME = 1.0 / TARGET_FPS

    # Physics limits
    MAX_SPEED_X = 0.4
    MAX_SPEED_Y = 0.2

    # Fish Behavior
    FISH_NEIGHBOR_RADIUS = 25.0
    FISH_COLLISION_RADIUS_X = 14.0
    FISH_COLLISION_RADIUS_Y = 6.0
    FISH_AVOID_FACTOR = 0.15
    FISH_TURN_STRENGTH = 0.05
    FISH_MARGIN_Y = 3
    FISH_MARGIN_X = 6

    # Spawn rates
    BUBBLE_CHANCE = 0.1

    # Colors
    COLOR_FISH = 1
    COLOR_BUBBLE = 3
    COLOR_PLANT = 4
    COLOR_FOOD = 5


# --- Assets ---
class Assets:
    """Sprite definitions."""

    FISH_LARGE_RIGHT = [
        ["  \\", " ><(((º>"],
        ["  /", " ><(((º>"],
    ]
    FISH_LARGE_LEFT = [
        ["  /", "<º)))>< "],
        ["  \\", "<º)))>< "],
    ]

    FISH_MEDIUM_RIGHT = [
        ["  __", "><(((º>"],
        ["  __", " >(((º>"],
    ]
    FISH_MEDIUM_LEFT = [
        [" __", "<º)))><"],
        [" __", "<º)))< "],
    ]

    FISH_SMALL_RIGHT = [[" ><> "], [" >()> "]]
    FISH_SMALL_LEFT = [[" <>< "], [" <()< "]]


# --- Base Entity ---
class Entity:
    """Base class for all moving objects in the aquarium."""

    def __init__(self, x: float, y: float, color_pair: int = 0):
        self.x = x
        self.y = y
        self.dx = 0.0
        self.dy = 0.0
        self.color_pair = color_pair
        self.width = 1
        self.height = 1

    def _move(self, dt: float):
        """Helper to apply velocity based on delta time."""
        # Scale movement by dt (normalized to approx 30fps for consistency with old physics)
        time_scale = dt / 0.05
        self.x += self.dx * time_scale
        self.y += self.dy * time_scale

    def _render(self, stdscr: Any, sprite: List[str]):
        """Helper to draw sprite safely."""
        try:
            attr = curses.color_pair(self.color_pair)
            for i, line in enumerate(sprite):
                draw_y = int(self.y) + i
                draw_x = int(self.x)
                if 0 <= draw_y < stdscr.getmaxyx()[0]:
                    stdscr.addstr(draw_y, draw_x, line, attr)
        except curses.error:
            pass


# --- Game Objects ---
class Fish(Entity):
    def __init__(self, max_y: int, max_x: int):
        super().__init__(
            x=random.uniform(1, max_x - 10),
            y=random.uniform(1, max_y - 4),
            color_pair=Config.COLOR_FISH,
        )

        # Personality & Physics
        self.speed_multiplier = random.uniform(0.7, 1.3)
        self.schooling_weight = random.uniform(0.5, 1.5)
        self.wander_angle = random.uniform(0, 2 * math.pi)

        # Initial Velocity
        self.dx = random.choice([-1, 1]) * random.uniform(0.1, 0.3)
        self.dy = random.uniform(-0.05, 0.05)
        self.face_right = True if self.dx > 0 else False

        # Determine Type
        self.type = random.choice(["small", "medium", "large"])
        if self.type == "large":
            self.frames_right = Assets.FISH_LARGE_RIGHT
            self.frames_left = Assets.FISH_LARGE_LEFT
        elif self.type == "medium":
            self.frames_right = Assets.FISH_MEDIUM_RIGHT
            self.frames_left = Assets.FISH_MEDIUM_LEFT
        else:  # small
            self.frames_right = Assets.FISH_SMALL_RIGHT
            self.frames_left = Assets.FISH_SMALL_LEFT

        self.frame_index = 0
        self.animation_timer = 0.0
        self.base_anim_speed = 0.25

        self.height = len(self.frames_right[0])
        self.width = len(self.frames_right[0][0])

    def update(
        self,
        dt: float,
        max_y: int,
        max_x: int,
        others: List["Fish"],
        foods: List["Food"],
    ):
        # 1. Variable Animation Speed
        # Speed varies based on actual velocity
        speed = math.hypot(self.dx, self.dy)
        anim_interval = self.base_anim_speed / max(0.5, speed * 4.0)

        self.animation_timer += dt
        if self.animation_timer >= anim_interval:
            self.animation_timer = 0
            self.frame_index = (self.frame_index + 1) % len(self.frames_right)

        # 2. Natural Wandering (Perlin-like steering)
        self.wander_angle += random.uniform(-0.2, 0.2)
        wander_force_x = math.cos(self.wander_angle) * 0.015
        wander_force_y = math.sin(self.wander_angle) * 0.015

        self.dx += wander_force_x
        self.dy += wander_force_y

        # 3. Subtle Vertical Drift (Buoyancy)
        self.dy += math.sin(time.time() * self.speed_multiplier + self.x) * 0.002

        # 4. Feeding Behavior
        self._handle_feeding(foods)

        # 5. Schooling & Separation
        self._handle_schooling(others)

        # 6. Boundary Check / Steering
        self._handle_boundaries(max_y, max_x)

        # 7. Apply Physics Limits (Personality based)
        limit_x = Config.MAX_SPEED_X * self.speed_multiplier
        limit_y = Config.MAX_SPEED_Y * self.speed_multiplier

        # Soft drag
        self.dx *= 0.99
        self.dy *= 0.99

        self.dx = max(-limit_x, min(limit_x, self.dx))
        self.dy = max(-limit_y, min(limit_y, self.dy))

        # 8. Move
        self._move(dt)

        # 9. Update Direction
        if self.dx > 0.05:
            self.face_right = True
        elif self.dx < -0.05:
            self.face_right = False

        # 10. Collisions
        self._handle_collisions(max_y, max_x)

    def _handle_feeding(self, foods: List["Food"]):
        if not foods:
            return

        nearest_food = None
        min_dist = float("inf")
        for food in foods:
            dist = abs(self.x - food.x) + abs(self.y - food.y)
            if dist < min_dist:
                min_dist = dist
                nearest_food = food

        if nearest_food:
            # Steer towards food
            self.dx += 0.05 if nearest_food.x > self.x else -0.05
            self.dy += 0.05 if nearest_food.y > self.y else -0.05

            # Consume
            mouth_x = self.x + (self.width if self.face_right else 0)
            mouth_y = self.y
            if (
                abs(mouth_x - nearest_food.x) < 2
                and abs(mouth_y - nearest_food.y) < 1.5
            ):
                nearest_food.consumed = True

    def _handle_schooling(self, others: List["Fish"]):
        avg_dx, avg_dy, avg_x, avg_y = 0.0, 0.0, 0.0, 0.0
        neighbors = 0

        # Personal space varies slightly
        separation_radius_x = Config.FISH_COLLISION_RADIUS_X * self.schooling_weight
        separation_radius_y = Config.FISH_COLLISION_RADIUS_Y * self.schooling_weight

        for other in others:
            if other is self:
                continue

            diff_x = self.x - other.x
            diff_y = self.y - other.y
            dist = (diff_x**2 + diff_y**2) ** 0.5

            if dist < Config.FISH_NEIGHBOR_RADIUS:
                avg_dx += other.dx
                avg_dy += other.dy
                avg_x += other.x
                avg_y += other.y
                neighbors += 1

            # Separation
            if abs(diff_x) < separation_radius_x and abs(diff_y) < separation_radius_y:
                factor = Config.FISH_AVOID_FACTOR * (1.5 if abs(diff_x) < 2 else 1.0)
                self.dx += factor if diff_x > 0 else -factor
                self.dy += factor if diff_y > 0 else -factor

        if neighbors > 0:
            avg_dx /= neighbors
            avg_dy /= neighbors
            avg_x /= neighbors
            avg_y /= neighbors

            # Alignment (match speed of group)
            self.dx += (avg_dx - self.dx) * 0.03 * self.schooling_weight
            self.dy += (avg_dy - self.dy) * 0.03 * self.schooling_weight

            # Cohesion (steer toward center of group)
            self.dx += (avg_x - self.x) * 0.005 * self.schooling_weight
            self.dy += (avg_y - self.y) * 0.005 * self.schooling_weight

    def _handle_boundaries(self, max_y: int, max_x: int):
        if self.y < Config.FISH_MARGIN_Y:
            self.dy += Config.FISH_TURN_STRENGTH
        elif self.y > max_y - Config.FISH_MARGIN_Y - self.height:
            self.dy -= Config.FISH_TURN_STRENGTH

        if self.x < Config.FISH_MARGIN_X:
            self.dx += Config.FISH_TURN_STRENGTH
        elif self.x > max_x - Config.FISH_MARGIN_X - self.width:
            self.dx -= Config.FISH_TURN_STRENGTH

    def _handle_collisions(self, max_y: int, max_x: int):
        if self.y < 1:
            self.y = 1
            self.dy *= -1
        elif self.y > max_y - 1 - self.height:
            self.y = max_y - 1 - self.height
            self.dy *= -1

        if self.x < 1:
            self.x = 1
            self.dx *= -1
            self.face_right = True
        elif self.x > max_x - 1 - self.width:
            self.x = max_x - 1 - self.width
            self.dx *= -1
            self.face_right = False

    def draw(self, stdscr):
        frames = self.frames_right if self.face_right else self.frames_left
        sprite = frames[self.frame_index]
        self._render(stdscr, sprite)


class Bubble(Entity):
    def __init__(self, max_y: int, max_x: int):
        super().__init__(
            x=random.uniform(1, max_x - 2),
            y=float(max_y - 2),
            color_pair=Config.COLOR_BUBBLE,
        )
        self.dy = random.uniform(-0.2, -0.05)
        self.char = random.choice(["o", "."])

    def update(self, dt: float):
        # Wiggle
        self.x += random.uniform(-0.1, 0.1)
        # Move up
        self._move(dt)

    def draw(self, stdscr):
        try:
            stdscr.addch(
                int(self.y), int(self.x), self.char, curses.color_pair(self.color_pair)
            )
        except curses.error:
            pass


class Food(Entity):
    def __init__(self, max_y: int, max_x: int):
        super().__init__(
            x=random.uniform(2, max_x - 2), y=1.0, color_pair=Config.COLOR_FOOD
        )
        self.dy = 0.15
        self.consumed = False

    def update(self, dt: float, max_y: int):
        self._move(dt)
        if self.y >= max_y - 2:
            self.y = float(max_y - 2)
            self.dy = 0

    def draw(self, stdscr):
        try:
            stdscr.addch(
                int(self.y), int(self.x), "*", curses.color_pair(self.color_pair)
            )
        except curses.error:
            pass


class Plant:
    """Static plant entity."""

    def __init__(self, x: int, max_y: int):
        self.x = x
        self.max_y = max_y
        self.type = random.choice(["seaweed", "coral", "kelp"])
        self.height = random.randint(3, 8)
        self.offset = random.random() * 10
        self.color_pair = Config.COLOR_PLANT

    def draw(self, stdscr, total_time: float):
        try:
            attr = curses.color_pair(self.color_pair)
            anim_tick = total_time * 20.0

            if self.type == "seaweed":
                for h in range(self.height):
                    dx = int(math.sin(anim_tick * 0.1 + h * 0.5 + self.offset) * 1.5)
                    char = "{" if (h + int(anim_tick * 0.1)) % 2 == 0 else "}"
                    stdscr.addch(self.max_y - 1 - h, self.x + dx, char, attr)
            elif self.type == "coral":
                for h in range(self.height // 2):
                    stdscr.addstr(self.max_y - 1 - h, self.x, "Y", attr)
                    if h > 0:
                        stdscr.addch(self.max_y - 1 - h, self.x - 1, "\\", attr)
                        stdscr.addch(self.max_y - 1 - h, self.x + 1, "/", attr)
            elif self.type == "kelp":
                for h in range(self.height):
                    dx = int(math.sin(anim_tick * 0.05 + h * 0.3 + self.offset) * 1.0)
                    stdscr.addstr(self.max_y - 1 - h, self.x + dx, "( )", attr)
        except curses.error:
            pass


def main(stdscr):
    # Engine Setup
    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(0)

    # Colors
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(Config.COLOR_FISH, curses.COLOR_YELLOW, -1)
        curses.init_pair(Config.COLOR_BUBBLE, curses.COLOR_CYAN, -1)
        curses.init_pair(Config.COLOR_PLANT, curses.COLOR_GREEN, -1)
        curses.init_pair(Config.COLOR_FOOD, curses.COLOR_WHITE, -1)

    # Initial Setup
    max_y, max_x = stdscr.getmaxyx()
    fishes = [Fish(max_y, max_x) for _ in range(8)]
    bubbles: List[Bubble] = []
    foods: List[Food] = []
    plants = [Plant(x, max_y) for x in range(2, max_x - 4, 8)]

    last_time = time.time()
    total_time = 0.0

    while True:
        current_time = time.time()
        dt = current_time - last_time
        last_time = current_time
        total_time += dt

        # Handle Resize
        new_max_y, new_max_x = stdscr.getmaxyx()
        if new_max_y != max_y or new_max_x != max_x:
            max_y, max_x = new_max_y, new_max_x
            plants = [Plant(x, max_y) for x in range(2, max_x - 4, 8)]

        # Input Handling
        key = stdscr.getch()
        if key in [ord("q"), 32, 10, 13, 27]:
            break
        elif key == ord("a"):
            fishes.append(Fish(max_y, max_x))
        elif key == ord("f"):
            foods.append(Food(max_y, max_x))

        # Bubble Spawning
        if random.random() < Config.BUBBLE_CHANCE * (dt / 0.05):
            bubbles.append(Bubble(max_y, max_x))

        # Update
        for fish in fishes:
            fish.update(dt, max_y, max_x, fishes, foods)

        for bubble in bubbles[:]:
            bubble.update(dt)
            if bubble.y < 1:
                bubbles.remove(bubble)

        for food in foods[:]:
            food.update(dt, max_y)
            if food.consumed:
                foods.remove(food)

        # Draw
        stdscr.erase()
        stdscr.box()

        for plant in plants:
            plant.draw(stdscr, total_time)
        for food in foods:
            food.draw(stdscr)
        for bubble in bubbles:
            bubble.draw(stdscr)
        for fish in fishes:
            fish.draw(stdscr)

        stdscr.refresh()

        # Frame Limiting
        elapsed = time.time() - current_time
        sleep_time = Config.FRAME_TIME - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)


if __name__ == "__main__":
    curses.wrapper(main)
