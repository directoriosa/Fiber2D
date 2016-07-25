/*
 * Cocos2D-SpriteBuilder: http://cocos2d.spritebuilder.com
 *
 * Copyright (c) 2014 Cocos2D Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "CCRendererBasicTypes.h"
#import "CCRenderer_Private.h"
#import "CCTexture_Private.h"
#import "CCMetalSupport_Private.h"
#import "CCCache.h"
#import "ccUtils.h"
#import "CCSetup.h"
#import "Fiber2D-Swift.h"

#pragma mark Blend Option Keys.
NSString * const CCRenderStateBlendMode = @"CCRenderStateBlendMode";
NSString * const CCRenderStateShader = @"CCRenderStateShader";
NSString * const CCRenderStateShaderUniforms = @"CCRenderStateShaderUniforms";

NSString * const CCBlendFuncSrcColor = @"CCBlendFuncSrcColor";
NSString * const CCBlendFuncDstColor = @"CCBlendFuncDstColor";
NSString * const CCBlendEquationColor = @"CCBlendEquationColor";
NSString * const CCBlendFuncSrcAlpha = @"CCBlendFuncSrcAlpha";
NSString * const CCBlendFuncDstAlpha = @"CCBlendFuncDstAlpha";
NSString * const CCBlendEquationAlpha = @"CCBlendEquationAlpha";


#pragma mark Blend Modes.
@interface CCBlendMode()

-(instancetype)initWithOptions:(NSDictionary *)options;

@end


@interface CCBlendModeCache : CCCache @end
@implementation CCBlendModeCache

-(id)objectForKey:(id<NSCopying>)options
{
	CCBlendMode *blendMode = [self rawObjectForKey:options];
	if(blendMode) return blendMode;
	
	// Normalize the blending mode to use for the key.
	id src = (options[CCBlendFuncSrcColor] ?: @(MTLBlendFactorOne));
	id dst = (options[CCBlendFuncDstColor] ?: @(MTLBlendFactorZero));
	id equation = (options[CCBlendEquationColor] ?: @(MTLBlendOperationAdd));
	
	NSDictionary *normalized = @{
		CCBlendFuncSrcColor: src,
		CCBlendFuncDstColor: dst,
		CCBlendEquationColor: equation,
		
		// Assume they meant non-separate blending if they didn't fill in the keys.
		CCBlendFuncSrcAlpha: (options[CCBlendFuncSrcAlpha] ?: src),
		CCBlendFuncDstAlpha: (options[CCBlendFuncDstAlpha] ?: dst),
		CCBlendEquationAlpha: (options[CCBlendEquationAlpha] ?: equation),
	};
	
	// Create the key using the normalized blending mode.
	blendMode = [super objectForKey:normalized];
	
	// Make an alias for the unnormalized version
	[self makeAlias:options forKey:normalized];
	
	return blendMode;
}

-(id)createSharedDataForKey:(NSDictionary *)options
{
	return options;
}

-(id)createPublicObjectForSharedData:(NSDictionary *)options
{
	return [[[CCBlendMode alloc] initWithOptions:options] autorelease];
}

// Nothing special
-(void)disposeOfSharedData:(id)data {}

-(void)flush
{
	// Since blending modes are used for keys, need to wrap the flush call in a pool.
	@autoreleasepool {
		[super flush];
	}
}

@end


@implementation CCBlendMode

-(instancetype)initWithOptions:(NSDictionary *)options
{
	if((self = [super init])){
		_options = [options retain];
	}
	
	return self;
}

-(void)dealloc
{
    [_options release]; _options = nil;
    
    [super dealloc];
}

static CCBlendModeCache *CCBLENDMODE_CACHE = nil;

// Default modes
static CCBlendMode *CCBLEND_DISABLED = nil;
static CCBlendMode *CCBLEND_ALPHA = nil;
static CCBlendMode *CCBLEND_PREMULTIPLIED_ALPHA = nil;
static CCBlendMode *CCBLEND_ADD = nil;
static CCBlendMode *CCBLEND_MULTIPLY = nil;

NSDictionary *CCBLEND_DISABLED_OPTIONS = nil;

+(void)initialize
{
	// +initialize may be called due to loading a subclass.
	if(self != [CCBlendMode class]) return;
	
	CCBLENDMODE_CACHE = [[CCBlendModeCache alloc] init];
	
	// Add the default modes
	CCBLEND_DISABLED = [[self blendModeWithOptions:@{}] retain];
	CCBLEND_DISABLED_OPTIONS = CCBLEND_DISABLED.options;
	
	CCBLEND_ALPHA = [[self blendModeWithOptions:@{
		CCBlendFuncSrcColor: @(MTLBlendFactorSourceAlpha),
		CCBlendFuncDstColor: @(MTLBlendFactorOneMinusSourceAlpha),
	}] retain];
	
	CCBLEND_PREMULTIPLIED_ALPHA = [[self blendModeWithOptions:@{
		CCBlendFuncSrcColor: @(MTLBlendFactorOne),
		CCBlendFuncDstColor: @(MTLBlendFactorOneMinusSourceAlpha),
	}] retain];
	
	CCBLEND_ADD = [[self blendModeWithOptions:@{
		CCBlendFuncSrcColor: @(MTLBlendFactorOne),
		CCBlendFuncDstColor: @(MTLBlendFactorOne),
	}] retain];
	
	CCBLEND_MULTIPLY = [[self blendModeWithOptions:@{
		CCBlendFuncSrcColor: @(MTLBlendFactorDestinationColor),
		CCBlendFuncDstColor: @(MTLBlendFactorZero),
	}] retain];
}

+(void)flushCache
{
	[CCBLENDMODE_CACHE flush];
}

+(CCBlendMode *)blendModeWithOptions:(NSDictionary *)options
{
	return [CCBLENDMODE_CACHE objectForKey:options];
}

+(CCBlendMode *)disabledMode
{
	return CCBLEND_DISABLED;
}

+(CCBlendMode *)alphaMode
{
	return CCBLEND_ALPHA;
}

+(CCBlendMode *)premultipliedAlphaMode
{
	return CCBLEND_PREMULTIPLIED_ALPHA;
}

+(CCBlendMode *)addMode
{
	return CCBLEND_ADD;
}

+(CCBlendMode *)multiplyMode
{
	return CCBLEND_MULTIPLY;
}

@end


#pragma mark Render States.

/// A simple key class for tracking render states.
/// ivars are unretained so that it doesn't force textures to stay in memory.
@interface CCRenderStateCacheKey : NSObject<NSCopying> @end
@implementation CCRenderStateCacheKey {
	@public
	__unsafe_unretained CCBlendMode *_blendMode;
	__unsafe_unretained CCShader *_shader;
	__unsafe_unretained CCTexture *_mainTexture;
	__unsafe_unretained CCTexture *_secondaryTexture;
}

-(instancetype)initWithBlendMode:(CCBlendMode *)blendMode shader:(CCShader *)shader mainTexture:(CCTexture *)mainTexture secondaryTexture:(CCTexture *)secondaryTexture
{
	if((self = [super init])){
		_blendMode = blendMode;
		_shader = shader;
		_mainTexture = mainTexture;
		_secondaryTexture = secondaryTexture;
	}
	
	return self;
}

-(NSUInteger)hash
{
	// Not great, but acceptable. All values are unique by pointer.
	return ((NSUInteger)_blendMode ^ (NSUInteger)_shader ^ (NSUInteger)_mainTexture);
}

-(BOOL)isEqual:(id)object
{
	CCRenderStateCacheKey *other = object;
	
	return (
		[other isKindOfClass:[CCRenderStateCacheKey class]] &&
		_blendMode == other->_blendMode &&
		_shader == other->_shader &&
		_mainTexture == other->_mainTexture &&
		_secondaryTexture == other->_secondaryTexture
	);
}

-(id)copyWithZone:(NSZone *)zone
{
	// Object is immutable.
	return self;
}

@end


@interface CCRenderStateCache : CCCache
@end


@implementation CCRenderStateCache

-(id)createSharedDataForKey:(CCRenderStateCacheKey *)key
{
	return key;
}

-(id)createPublicObjectForSharedData:(CCRenderStateCacheKey *)key
{
    NSDictionary *uniforms = @{
        CCShaderUniformMainTexture: key->_mainTexture,
        CCShaderUniformSecondaryTexture: key->_secondaryTexture,
    };
    
	// Although the key ivars are unretained, this method is only ever called when a key has been freshly constructed using strong references to the necessary objects.
	return [CCRenderStateMetal renderStateWithBlendMode:key->_blendMode shader:key->_shader shaderUniforms:uniforms copyUniforms:YES];
}

// Nothing special
-(void)disposeOfSharedData:(id)data {}

-(void)flush
{
	// Since render states are used for keys, need to wrap the flush call in a pool.
	@autoreleasepool {
		[super flush];
	}
}

@end


@implementation CCRenderState

static CCRenderStateCache *CCRENDERSTATE_CACHE = nil;
static CCRenderState *CCRENDERSTATE_DEBUGCOLOR = nil;

+(void)initialize
{
	// +initialize may be called due to loading a subclass.
	if(self != [CCRenderState class]) return;
	
	CCRENDERSTATE_CACHE = [[CCRenderStateCache alloc] init];
	CCRENDERSTATE_DEBUGCOLOR = [[CCRenderStateMetal alloc] initWithBlendMode:CCBLEND_DISABLED shader:[CCShader positionColorShader] shaderUniforms:@{} copyUniforms:YES];
}

+(void)flushCache
{
	[CCRENDERSTATE_CACHE flush];
}

-(instancetype)initWithBlendMode:(CCBlendMode *)blendMode shader:(CCShader *)shader shaderUniforms:(NSDictionary *)shaderUniforms copyUniforms:(BOOL)copyUniforms
{
	if((self = [super init])){
		NSAssert(blendMode, @"CCRenderState: Blending mode is nil");
		NSAssert(shader, @"CCRenderState: Shader is nil");
		NSAssert(shaderUniforms, @"CCRenderState: shader uniform dictionary is nil.");
		
		_blendMode = [blendMode retain];
		_shader = [shader retain];
		_shaderUniforms = (copyUniforms ? [shaderUniforms copy] : [shaderUniforms retain]);
		
		// The renderstate as a whole is immutable if the uniforms are copied.
		_immutable = copyUniforms;
	}
	
	return self;
}

-(void)dealloc
{
    [_blendMode release]; _blendMode = nil;
    [_shader release]; _shader = nil;
    [_shaderUniforms release]; _shaderUniforms = nil;
    
    [super dealloc];
}

+(instancetype)renderStateWithBlendMode:(CCBlendMode *)blendMode shader:(CCShader *)shader mainTexture:(CCTexture *)mainTexture;
{
    return [self renderStateWithBlendMode:blendMode shader:shader mainTexture:mainTexture secondaryTexture:[CCTexture none]];
}

+(instancetype)renderStateWithBlendMode:(CCBlendMode *)blendMode shader:(CCShader *)shader mainTexture:(CCTexture *)mainTexture secondaryTexture:(CCTexture *)secondaryTexture;
{
	if(mainTexture == nil){
		CCLOGWARN(@"nil Texture passed to CCRenderState");
		mainTexture = [CCTexture none];
	}
	
	if(secondaryTexture == nil){
		CCLOGWARN(@"nil Texture passed to CCRenderState");
		secondaryTexture = [CCTexture none];
	}
	
    CCRenderStateCacheKey *key = [[CCRenderStateCacheKey alloc] initWithBlendMode:blendMode shader:shader mainTexture:mainTexture secondaryTexture:secondaryTexture];
    CCRenderState *renderState = [CCRENDERSTATE_CACHE objectForKey:key];
    [key release];
    
    return renderState;
}

+(instancetype)renderStateWithBlendMode:(CCBlendMode *)blendMode shader:(CCShader *)shader shaderUniforms:(NSDictionary *)shaderUniforms copyUniforms:(BOOL)copyUniforms
{
	return [[[CCRenderStateMetal alloc] initWithBlendMode:blendMode shader:shader shaderUniforms:shaderUniforms copyUniforms:copyUniforms] autorelease];
}

-(id)copyWithZone:(NSZone *)zone
{
	if(_immutable){
		return [self retain];
	} else {
		return [[CCRenderStateMetal allocWithZone:zone] initWithBlendMode:_blendMode shader:_shader shaderUniforms:_shaderUniforms copyUniforms:YES];
	}
}

+(instancetype)debugColor
{
	return CCRENDERSTATE_DEBUGCOLOR;
}

-(void)transitionRenderer:(CCRenderer *)renderer FromState:(CCRenderer *)previous
{
	NSAssert(NO, @"Must be overridden.");
}

@end


// MARK: CCGraphicsBuffer


@implementation CCGraphicsBuffer

-(instancetype)initWithCapacity:(NSUInteger)capacity elementSize:(size_t)elementSize type:(CCGraphicsBufferType)type
{
	if((self = [super init])){
		_count = 0;
		_capacity = capacity;
		_elementSize = elementSize;
	}
	
	return self;
}

-(void)resize:(size_t)newCapacity
{NSAssert(NO, @"Must be overridden.");}

-(void)destroy
{NSAssert(NO, @"Must be overridden.");}

-(void)prepare
{NSAssert(NO, @"Must be overridden.");}

-(void)commit
{NSAssert(NO, @"Must be overridden.");}

-(void)dealloc
{
	[self destroy];
    [super dealloc];
}

@end


#pragma mark CCGraphicsBufferBindings


@implementation CCGraphicsBufferBindings

-(void)dealloc
{
    [_vertexBuffer release]; _vertexBuffer = nil;
    [_indexBuffer release]; _indexBuffer = nil;
    [_uniformBuffer release]; _uniformBuffer = nil;
    
    [super dealloc];
}

// Base implementation does nothing.
-(void)bind:(BOOL)bind vertexPage:(NSUInteger)vertexPage {}

-(void)prepare
{
	[_vertexBuffer prepare];
	[_indexBuffer prepare];
	[_uniformBuffer prepare];
}

-(void)commit
{
	[_vertexBuffer commit];
	[_indexBuffer commit];
	[_uniformBuffer commit];
}

@end


#pragma mark Framebuffer bindings.


@implementation CCFrameBufferObject

-(instancetype)initWithTexture:(CCTexture *)texture depthStencilFormat:(MTLPixelFormat)depthStencilFormat
{
	if((self = [super init])){
		_texture = [texture retain];
		
		_sizeInPixels = CC_SIZE_SCALE(texture.contentSize, texture.contentScale);
		_contentScale = texture.contentScale;
	}
	
	return self;
}

-(void)dealloc
{
    [_texture release]; _texture = nil;
    
    [super dealloc];
}

-(void)bindWithClear:(MTLLoadAction)mask color:(GLKVector4)color4
{NSAssert(NO, @"Must be overridden.");}

-(void)syncWithView:(MetalView *)view;
{
	self.sizeInPixels = view.sizeInPixels;
	self.contentScale = [CCSetup sharedSetup].contentScale;
}

@end